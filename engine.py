from typing import Set, Callable, Tuple, Dict
import numpy as np

class NoValue:
    """Represents a null value in a CalcNode.
    """
    def __init__(self):
        pass

class Bar(int):
    pass

class Asset:
    def __init__(self):
        pass

class Field:
    def __init__(self):
        pass

class AssetFieldId:
    def __init__(self, asset_id: Asset, field_id: Field):
        self.asset_id, self.field_id = asset_id, field_id


class CalcNode:
    """Represents a single value in our program. If we imagine a 3D lattice of data points, where
    the dimensions are (bars, assets, fields), then these would be the nodes in that lattice.
    """

    def __init__(self, operation: Callable[ [ Dict[Tuple[Bar, Asset, Field], object] ], object ], 
        downstream_nodes: Set=set(), value: object=NoValue(), 
        all_assets_depend: bool=False, all_fields_depend: bool=False):
        """Make a CalcNode!

        Arguments:
            operation {Callable[ [ Dict[Tuple[Bar, Asset, Field], CalcNode] ], object ]} -- Operation to apply 
                on the inputs to the CalcNode.

        Keyword Arguments:
            downstream_nodes {Set[CalcNode]} -- Nodes that directly depend on this node for computation; 
                if not specified, then all_assets_depend or all_fields_depend must be True. (default: {set()})
            value {object} -- The value that the node gets after its computation was performed. (default: {NoValue()})
            all_assets_depend {bool} -- Flags True iff all assets in a given bar depend on this CalcNode in order
            to compute (default: {False})
            all_fields_depend {bool} -- Flags True iff all fields in this CalcNodes's bar depend on this CalcNode in order
            to compute (default: {False})
        """
        self.downstream_nodes = downstream_nodes
        self.value = value
        self.all_assets_depend = all_assets_depend
        self.all_fields_depend = all_fields_depend

        # implementation
        self.__dependency_degree = -1 # used as a rough metric to prioritize which nodes to compute first

def __example_operation(input: Dict[Tuple[Bar, Asset, Field], CalcNode]) -> object:
    """Example of how a CalcNode operation may be defined.

    Arguments:
        input {Dict[Tuple[Bar, Asset, Field], CalcNode]} -- Mapping from a CalcNode's identifiers to the CalcNode

    Returns:
        object -- Any object that is to become the value of the operation.
    """
    pass

class CalcLattice:
    """A structured collection of CalcNodes. This lattice is a DAG. The main utility 
    that comes from this data structure is the ability to run CalcNodes
    that depend on other CalcNodes for input. We can also inject input in in the
    form of seed values. In the context of a financial data backtest, seed values may
    be OHLCV data; however, this lattice could also represent the input of any data that may
    have a cascading effect on other CalcNodes (like the input layer of a neural net).
    
    For example, if we had a streaming connection to Trump's twitter, we may 'inject'
    his tweet into our lattice, then calculate the values in CalcNodes using not only
    that tweet, but also all of the previous CalcNodes (or at least the number of lookback bars
    that we care about). Perhaps we design a system that finds the rolling average of the
    standard deviation of word lengths in his tweets, and then if the short term rolling
    average crosses over or under the long term moving average, we signal that Trump's tweet
    words are becoming shorter/longer. While this is just a toy example, this architecture
    can be built upon to do much larger jobs.
    """
    
    def __init__(self, num_bars: int, num_assets: int, num_fields: int, num_bars_stored: int=-1):
        self.num_bars, self.num_assets, self.num_fields, = num_bars, num_bars, num_fields
        self.num_bars_stored = num_bars if (num_bars_stored == -1) else num_bars_stored
        
        # Implementation
        self.__recent_bars = np.zeros(shape=num_bars_stored, dtype=object)
        self.__cur_bar_index = -1 # since we increment first when we inject a value, this must start at -1

    def __cur_bar_index_inc_n(self, n: int):
        return (self.__cur_bar_index + n) % self.num_bars_stored
    
    def __cur_bar_index_inc(self):
        return self.__cur_bar_index_inc_n(1)

    def inject(self, new_bar_data: Dict[AssetFieldId, CalcNode]):
        """Inject data for a new bar!

        Arguments:
            new_bar_data {Dict[AssetFieldId, CalcNode]} -- Mapping from BarData identifiers to CalcNode.
        """
        
        self.__cur_bar_index = self.__cur_bar_index_inc()
        
        self.__recent_bars[self.__cur_bar_index] = new_bar_data

        return

    def get_n_bar_ago_data(self, ago: int) -> Dict[AssetFieldId, CalcNode]:
        """Returns all of the KV pairs for asset-field -> CalcNodes n bars ago.

        Arguments:
            ago {int} -- Number of bars ago to get data. If 0, then this is the same as get_cur_bar_data.

        Raises:
            ValueError: If the `ago` is not an instance of an int.
            ValueError: If `ago` is negative.

        Returns:
            Dict[AssetFieldId, CalcNode] -- all of the KV pairs for asset-field -> CalcNodes n bars ago.
        """
        if not isinstance(ago, int):
            raise ValueError('Wrong type for `ago`; expected {}, got {}'.format(int, type(ago)))
        elif ago < 0:
            raise ValueError('`ago` MUST be a non-negative intege!')
        elif ago >= self.num_bars_stored:
            raise ValueError('Cannot access {} bars ago, since there are only {} bars stored.' + 
                ' Acceptable input is in the range [0, {}]'.format(ago, self.num_bars_stored, self.num_bars_stored-1))
        
        return self.__recent_bars[self.__cur_bar_index_inc_n(-ago)]

    def get_cur_bar_data(self) -> Dict[AssetFieldId, CalcNode]:
        """Returns all of the KV pairs for asset-field -> CalcNodes in the current bar.

        Returns:
            Dict[AssetFieldId, CalcNode] -- all of the KV pairs for asset-field -> CalcNodes in the current bar.
        """
        return get_n_bar_ago_data(0)
    
    pass



'''
What I want to do:
    + Make a feed-forward graph execution system (maybe eventually port to TF?)
    + 
'''


'''
START_CALCULATION
    Make a distributed mapping FROM dependency precedence TO set of calcnodes with that precedence that haven't been calculated.
    For each precedence:
        Pop off a CalcNode
        if can calculate the node:
            Calculate the node
            Calculate all downstream nodes
        else:
            place CalcNode back into the set

'''