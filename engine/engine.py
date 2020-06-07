""" Infrastructure for processing Window and CrossSectional operations.
This utilizes a graph data structure.
"""
from typing import Set, Callable, Dict, Any
from abc import ABC, abstractmethod
import numpy as np
import pandas as pd
from engine.engine_utils import AssetId, FieldId, AssetFieldId, BadDAGException, StaticDAGException, DAGStatusCodes
import engine.fields.fields as fields
from collections import Counter

# CalcNode - the smalles unit in a CalcLattice
# class CalcNode:
    #     """Represents a single value in our lattice. If we imagine a 3D lattice of data points, where
    #     the dimensions are (bars, assets, fields), then these would be the nodes in that lattice.
    #     """

    #     def __init__(self, value):
    #         self.value = value
    #         return


# BarLayer - a bag of Values that are all on the same bar
class BarLayer:
    """Dict-like data structure for inserting and accessing values for a given bar.
    """
    def __init__(self):
        self.__bar_data: Dict[AssetFieldId, Any] = {}

    def get_value(self, asset_id: AssetId, field_id: FieldId) -> Any:
        asset_field_id = AssetFieldId(asset_id, field_id)

        if asset_field_id not in self.__bar_data:
            raise ValueError("There's no node in this layer with asset_id={} and field_id={}.".format(asset_id, field_id))
        return self.__bar_data[asset_field_id]

    def insert_value(self, asset_id: AssetId, field_id: FieldId, node: Any) -> None:
        self.__bar_data[AssetFieldId(asset_id, field_id)] = node
        return

    def get_all_values(self):
        return self.__bar_data

    def __repr__(self):
        return self.__bar_data.__repr__()
    pass


# CalcLattice - an ordered collection of BarLayers
class CalcLattice:
    """A structured collection of Values. This lattice is a DAG. The main utility 
        that comes from this data structure is the ability to run Values
        that depend on other Values for input. We can also inject input in in the
        form of seed values. In the context of a financial data backtest, seed values may
        be OHLCV data; however, this lattice could also represent the input of any data that may
        have a cascading effect on other Values (like the input layer of a neural net).
        
        For example, if we had a streaming connection to Trump's twitter, we may 'inject'
        his tweet into our lattice, then calculate the values in Values using not only
        that tweet, but also all of the previous Values (or at least the number of lookback bars
        that we care about). Perhaps we design a system that finds the rolling average of the
        standard deviation of word lengths in his tweets, and then if the short term rolling
        average crosses over or under the long term moving average, we signal that Trump's tweet
        words are becoming shorter/longer. While this is just a toy example, this architecture
        can be built upon to do much larger jobs.
    """
    
    def __init__(self, num_bars_stored: int, asset_ids: Set[AssetId]):

        # Attributes that remain constant
        self.__asset_ids = asset_ids
        self.__num_assets = len(self.__asset_ids)
        self.__num_bars_stored = num_bars_stored

        # Attributes maintaining storage and access of bars
        self.__cur_bar_index = -1 # since we increment first when we inject a value, this must start at -1
        self._num_bars_completed = -1 # tracks cur bar index, but never resets to 0
        self.__recent_bars = np.zeros(shape=self.__num_bars_stored, dtype=object)
        # print('Recent bars: {}'.format(self.__recent_bars))
        
        # Attributes that reset each bar
        self.__num_assets_completed = Counter() # map from field to the number of assets completed for that field; resets after each bar

        # Attributes that get modified when new fields are added
        self.__window_dep_fields: Dict[FieldId, Set[FieldId]] = {} # map from depended field to fields that depend on it (e.g. OPEN -> [30_MAVG_OPEN, 15_MAVG_OPEN])
        self.__cross_sectional_fields: Dict[FieldId, Set[FieldId]] = {} # map from depended field to fields that depend on it (e.g. OPEN -> [Cross_STDDEV_OPEN, Cross_DECILE_OPEN])
        self.__field_to_field_op: Dict[FieldId, fields.FieldOp] = {} 

    def __cur_bar_index_inc_n(self, n: int):
        return (self.__cur_bar_index + n) % self.__num_bars_stored
    
    def __cur_bar_index_inc(self):
        return self.__cur_bar_index_inc_n(1)

    def __get_n_bar_ago_data(self, ago: int) -> BarLayer:
        """Returns a representation of all Values for the current bar.

        Arguments:
            ago {int} -- Number of bars ago to get data. If 0, then this is the same as get_cur_bar_data.

        Raises:
            ValueError: If `ago` is not an instance of an int.
            ValueError: If `ago` is negative.
            ValueError: If `ago` exceeds the number of bars stored.
            IndexError: If `ago` exceeds the number of bars already computed.

        Returns:
            BarLayer -- a representation of all Values for the current bar.
        """
        if not isinstance(ago, int):
            raise ValueError('Wrong type for `ago`; expected {}, got {}'.format(int, type(ago)))
        elif ago < 0:
            raise ValueError('`ago` MUST be a non-negative integer!')
        elif ago >= self.__num_bars_stored:
            raise ValueError('Cannot access {} bars ago, since there are only {} bars stored.'.format(ago, self.num_bars_stored) + 
                ' Acceptable input is in the range [0, {}].'.format(self.num_bars_stored-1))
        elif ago > self._num_bars_completed:
            raise IndexError('Accessing data from {} bars ago, but at most only {} bars of data have been fully computed.'.format(ago, self._num_bars_completed))
        res = self.__recent_bars[self.__cur_bar_index_inc_n(-ago)]
        # print('CBI: {}'.format(self.__cur_bar_index))
        print('Recent Bars:\n{}'.format(self.__recent_bars))
        return res

    def __get_cur_bar_data(self) -> BarLayer:
        """Returns a representation of all Values for the current bar.

        Returns:
            BarLayer -- a representation of all Values for the current bar.
        """
        return self.__get_n_bar_ago_data(0)
    
    # def __get_n_bar_ago_values(self, ago: int) -> Dict[AssetFieldId, Any]:
    #     all_nodes = self.__get_n_bar_ago_data(ago).get_all_values()
    #     return {key : all_nodes[key].value for key in all_nodes}

    def _get_n_bar_ago_field_data(self, ago: int, field_id: FieldId) -> Dict[AssetId, Any]:
        """Make a mapping from AssetId to values for a specific field `ago` bars ago.

        Args:
            ago (int): Number of bars ago on which to find data.
            field_id (FieldId): Identifier of which field to get the data for.

        Returns:
            Dict[AssetId, Any]: mapping from AssetId to values for a specific field `ago` bars ago.
        """
        # TODO: perform operation in parallel over the different AssetFieldId keys

        values = self.__get_n_bar_ago_data(ago).get_all_values()
        asset_id_to_value: Dict[AssetId, Any] = {}
        for asset_field_id in values:
            if (asset_field_id.get_field_id() == field_id):
                asset_id_to_value[asset_field_id.get_asset_id()] = values[asset_field_id]
        return asset_id_to_value
        
    def _get_cur_bar_field_data(self, field_id: FieldId) -> Dict[AssetId, Any]:
        return self._get_n_bar_ago_field_data(0, field_id)
    
    def __insert_node_in_cur_layer(self, asset_id: AssetId, field_id: FieldId, value: Any):
        self.__recent_bars[self.__cur_bar_index].insert_value(asset_id, field_id, value)
    
    def __inject_and_propagate(self, new_bar_data: Dict[AssetId, Dict[FieldId, Any]]):
        """Inject data for a new bar!
        This modifies state that tracks the current bar, so it's imperative that this not
        be invoked more than once per bar.
        
        NOTE: THIS METHOD MODIFIES PROGRAM STATE.

        Arguments:
            new_bar_data {Dict[AssetId, Dict[FieldId, Any]]} -- Mapping from BarData identifiers to Value.
        """

        self.__cur_bar_index = self.__cur_bar_index_inc() # NOTE: modifies state
        self._num_bars_completed += 1 # NOTE: modifies state

        new_bar_layer = BarLayer()
        self.__recent_bars[self.__cur_bar_index] = new_bar_layer # NOTE: modifies state

        field_ids = list(new_bar_data[ list(new_bar_data.keys())[0] ].keys()) # NOTE: assumes all assets have the same fields (not the only time this assumption is made)
        for asset_id in new_bar_data:
            for field_id in field_ids:
                value = new_bar_data[asset_id][field_id]
                self.__insert_node_in_cur_layer(asset_id, field_id, value)

        # propagate all genesis fields
        for gen_field_id in field_ids:
            self.__propagate_from_genesis_field(gen_field_id)

        return
    
    def __propagate_from_genesis_field(self, gen_field_id: FieldId):

        # Propagate forward all window fields that depend on this asset
        if gen_field_id in self.__window_dep_fields:
            window_gen_dep_fields = self.__window_dep_fields[gen_field_id] # window fields depending on genesis
            for window_field_id in window_gen_dep_fields:
                for asset_id in self.__asset_ids:
                    self.__propagate(asset_id, window_field_id)

        # Compute cross sectional results, then propagate forward
        if gen_field_id in self.__cross_sectional_fields:
            for cross_section_field_id in self.__cross_sectional_fields[gen_field_id]:
                dep_field_op = self.__field_to_field_op[cross_section_field_id]
                dep_field_results = dep_field_op.execute_op()
                for dep_asset_id in self.__asset_ids:
                    self.__propagate(dep_asset_id, cross_section_field_id, dep_field_results)

    
    def __propagate(self, asset_id: AssetId, field_id: FieldId, cross_sectional_results: pd.Series = None) -> None:
        """Assuming that all of the nodes' dependencies have already been computed, (a) compute this node's value, and
        (b) recursively propagate forward by calling __propagate on any nodes whose dependencies are satisfied after this
        node's completion.
        NOTE: THIS FUNCTION MODIFIES STATE!!

        Args:
            asset_field_id (AssetFieldId) - specifies the "address" of the node to be computed.
        """
        # Compute the node's value and add it to data.
        field_op = self.__field_to_field_op[field_id]
        if isinstance(field_op, fields.WindowOp):
            result = field_op.execute_op(asset_id)
        elif isinstance(field_op, fields.CrossSectionalOp):
            if not isinstance(cross_sectional_results, pd.Series):
                raise ValueError('Attempted to perform a cross sectional operation. '+
                                'Expected cross_sectional_results to be of type {}, but it was of type {}.'.format(pd.Series, type(cross_sectional_data)))
            result = cross_sectional_results[asset_id]
        elif isinstance(field_op, fields.InjectionOp):
            result = None
        else:
            raise ValueError('Encountered unidentified field operation with type: {}.'.format(type(field_op)))

        if result:
            self.__insert_node_in_cur_layer(asset_id, field_id, result) # NOTE: modifies state of the CalcLattice data

        # Propagate window calculations forward
        if field_id in self.__window_dep_fields:
            for window_field_id in self.__window_dep_fields[field_id]:
                self.__propagate(asset_id, window_field_id)

        # Propagate cross sectional calculations forward if this field has all of its assets completed
        self.__num_assets_completed[field_id] += 1 # NOTE: modifies state
        if field_id in self.__cross_sectional_fields:
            if self.__num_assets_completed[field_id] == self.__num_assets:
                for cross_section_field_id in self.__cross_sectional_fields[field_id]:
                    dep_field_op = self.__field_to_field_op[cross_section_field_id]
                    dep_field_results = dep_field_op.execute_op()
                    for dep_asset_id in self.__asset_ids:
                        self.__propagate(dep_asset_id, cross_section_field_id, dep_field_results)
        
        return

    def __check_DAG(self) -> int:
        # TODO: add functionality to check that the dependency graph is non-circular and that all fields are reachable from the seed fields
        return DAGStatusCodes.OK

    def new_bar(self, new_bar_data: Dict[AssetId, Dict[FieldId, Any]]):
        dag_status_code = self.__check_DAG()
        if (self.__cur_bar_index == -1) and (dag_status_code != DAGStatusCodes.OK):
            raise BadDAGException(dag_status_code)
        
        # TODO: Add new bar data, and call compute on each field that's added
        self.__inject_and_propagate(new_bar_data)

        # print(self.__recent_bars)

        self.__num_assets_completed = Counter()
    
    def add_field(self, field: fields.Field):
        """Prepare the CalcLattice to execute this field.

        Args:
            field (fields.Field): Specification of the indicator to be used.
        """
        # print('Field: {}'.format(field.__dict__))

        if (self.__cur_bar_index != -1):
            raise StaticDAGException()

        def append_to_dict(d: Dict, key, val):
            if key not in d:
                d[key] = []
            d[key].append(val)
        
        if field.field_id in self.__field_to_field_op:
            raise Exception('A field with the name `{}` already exists. Cannot have two fields with the same name.'.format(field.field_id))
        
        # print(self.__field_to_field_op.keys())

        is_window_op = issubclass(field.field_operation, fields.WindowOp)
        is_cross_sectional_op = issubclass(field.field_operation, fields.CrossSectionalOp)
        is_injection_op = issubclass(field.field_operation, fields.InjectionOp)

        if is_window_op or is_cross_sectional_op:
            self.__field_to_field_op[field.field_id] = field.field_operation(
                lattice=self,
                **field.field_op_input
            )
        
        if is_window_op:
            append_to_dict(self.__window_dep_fields, field.dependent_field_id, field.field_id)
        elif is_cross_sectional_op:
            append_to_dict(self.__cross_sectional_fields, field.dependent_field_id, field.field_id)
        elif is_injection_op:
            pass # only the operations that depend on other fields need to be added to the dictionaries
        else:
            raise ValueError('Unknown type for attribute `field_operation` of field: {}'.format(type(field.field_operation)))

        pass
        
    def __str__(self):
        s = ''
        for ago in range(self.__num_bars_stored-1, -1, -1):
            s += str(self.__get_n_bar_ago_data(ago))+'\n'
        return s

    def __repr__(self):
        return str(self)


if __name__ == "__main__":
    ''' Small BarLayer test; NOTE: this is not indicative of values that we would actually use in a BarLayer object.
    bl = BarLayer()
    bl.insert_value('a', 'f', 'n')
    print(bl.get_value('a', 'f')) # should return 'n'
    print(bl.get_value('a', 'g')) # should throw a ValueError
    '''
    import time
    start = time.time()
    num_bars_ = 5
    asset_ids_ = {AssetId('AAPL'), AssetId('MSFT'), AssetId('TSLA')}
    _lattice = CalcLattice(num_bars_, asset_ids_)

    ## Adding fields ##
    fields_ = [
        fields.Field({
            'field_operation': fields.InjectionOp,
            'field_id': FieldId('Open')
        }),
        # fields.Field({
        #     'field_operation': fields.InjectionOp,
        #     'field_id': FieldId('Close')
        # })
    ]

    # n_mavg = 1
    # fields_ += [
    #     fields.Field({
    #         'field_operation': fields.SMA,
    #         'field_id': FieldId(f'MAVG-Open-{i}'),
    #         'dependent_field_id': FieldId('Open'),
    #         'window_len': i
    #     })
    #     for i in range(2, n_mavg+2)
    # ]

    fields_ += [
        fields.Field({
            'field_operation': fields.Z_Score,
            'field_id': FieldId(f'ZScore-Open'),
            'dependent_field_id': FieldId('Open'),
        })
    ]

    ## Adding fields to lattice ##
    for field in fields_:
        _lattice.add_field(field)

    ## Adding data ##
    range_ = range(1, num_bars_+1)
    all_bars = { i :
        {AssetId('AAPL'): {FieldId('Open'): i*10, FieldId('Close'): i*20},
        AssetId('MSFT'):  {FieldId('Open'): i*20, FieldId('Close'): i*25},
        AssetId('TSLA'):  {FieldId('Open'): i*1, FieldId('Close'): i*.01}
        }
        for i in range_
    }

    ## Running! ##
    for i in range_:
        _lattice.new_bar(all_bars[i])
        print('\n\n\n\n\n')

    print(_lattice)
    
    print('Took {} seconds.'.format(time.time()-start))
    print(_lattice._CalcLattice__asset_ids)

    pass

# '''
# CalcLattice is implemented as a list (or np array) of length NUM_BARS_TO_KEEP, where each element in the array
# contains a BarLayer object. If we think of the lattice as a 3D prism with dimensions (bars, assets, fields), then
# a BarLayer represents all of the asset-field pairs in a given bar.

# '''