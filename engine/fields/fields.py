"""Implementation of fields and their parent classes.
"""
from typing import Any, Dict, Type
from abc import ABC, abstractmethod
import pandas as pd
from numpy import nan
import inspect
from warnings import warn
from engine.engine_utils import FieldId, AssetId
from engine.fields.field_utils import \
    get_field_op_user_args, get_field_op_user_optional_args, \
    get_field_op_user_required_args, PROHIBITED_USER_PROVIDED_FIELD_ATTRIBUTES,\
    FIELD_OPERATION_KW, FIELD_ID_KW, DEP_FIELD_ID_KW


# Field operation base classes - defining what behavior should occur at a given field.
class FieldOp(ABC):
    """Abstract class for operations to be performed on a particular field.
    """
    def __init__(self, dependent_field_id: FieldId, field_id: FieldId, lattice):
        """ Base initialization method.
        Args:
            dependent_field_id (FieldId): field that is used to compute this operation 
                (e.g. 30_DAY_MAVG_OPEN may depend have 'OPEN' as a dependent_field_id)
            field_id (str): Name of the operation that is to be carried out (e.g. SMA, or STDEV)
            lattice (CalcLattice): lattice containing all of the data 
                # NOTE: if type was added, it would cause a circular dependency. (CalcLattice -> fields -> CalcLattice)
        """
        self._dependent_field_id = dependent_field_id
        self._field_name = field_id
        self._lattice = lattice
        return

    @abstractmethod
    def execute_op(self):
        pass
    

class InjectionOp(FieldOp):
    """Operation to be performed on injected data. Does nothing.
    """
    def __init__(self, field_id: FieldId):
        self._field_name = field_id
        pass
    
    # must implement in order to inherit from FieldOp and be initializable
    def execute_op(self):
        raise RuntimeError('Cannot run `execute_op` for InjectionOp.')

    def make_field_name(self):
        raise RuntimeError('Cannot run `make_field_name` for InjectionOp.')
    

class WindowOp(FieldOp):
    def __init__(self, window_len: int, dependent_field_id: FieldId, field_id: FieldId, lattice):
        """Implementation of a windowed calculation on data. Here, the field and asset are fixed,
        while the bar is variable.

        Args:
            window_len (int): Number of bars over which to make the calculation.
            dependent_field_id (FieldId): See FieldOp docstring.
            field_id (str): See FieldOp docstring.
            lattice (CalcLattice): See FieldOp docstring.
        """

        super().__init__(dependent_field_id, field_id, lattice)
        self.__window_len = window_len
        
    def __get_window_of_data(self, asset_id: AssetId) -> pd.Series:
        
        windowlen = min(self.__window_len, self._lattice._num_bars_completed+1)

        return pd.Series({
            ago : self._lattice._get_n_bar_ago_field_data(ago, self._dependent_field_id)[asset_id]
            for ago in range(windowlen)
        })

    def partial_data_op(self, data: pd.Series) -> Any:
        """Default behavior to perform when there is not enough prior data
        for fill a window. We simply return numpy.nan for the reduction.

        Args:
            data (pd.Series): Mapping from asset_ids to values.

        Returns:
            np.nan
        """
        return nan
    
    @abstractmethod
    def op(self, data: pd.Series) -> Any:
        pass

    def execute_op(self, asset_id: AssetId) -> Any:
        data = self.__get_window_of_data(asset_id)
        if len(data) == self.__window_len:
            return self.op(data)
        elif len(data) < self.__window_len:
            return self.partial_data_op(data)
        else:
            raise Exception('There is more data than requested.')


class CrossSectionalOp(FieldOp):
    def __init__(self, dependent_field_id: FieldId, field_id: FieldId, lattice):
        """Cross sectional calculation on data. Here, field and bar are fixed, while the asset is variable.

        Args:
            dependent_field_id (FieldId): See FieldOp docstring.
            field_id (str): See FieldOp docstring.
            lattice (CalcLattice): See FieldOp docstring.
        """
        super().__init__(dependent_field_id, field_id, lattice) 

    def __gather_asset_data(self) -> pd.Series:
        asset_id_to_field_values = self._lattice._get_cur_bar_field_data(self._dependent_field_id)
        return pd.Series(asset_id_to_field_values)

    @abstractmethod
    def op(self, data: pd.Series) -> pd.Series:
        pass
    
    def execute_op(self) -> pd.Series:
        """Map from the dependent field's assets to this field's assets.

        Returns:
            pd.Series: Series where index is asset names, and values are the values for the
                nodes in this (bar, field, asset).
        """
        data = self.__gather_asset_data()
        return self.op(data)


# Field operation derived classes - ready for use within a pipeline.
# TODO: Add more indicators!

# Derived window operations
class SMA(WindowOp):
    def op(self, data: pd.Series) -> pd.Series:
        return (data.sum() / data.size)


# Derived cross sectional operations
class Z_Score(CrossSectionalOp):
    def op(self, data: pd.Series):
        """Compute the relative z-score of each asset by computing
            (a) the standard deviation among assets,
            (b) the mean among assets, and
            (c) the number of standard deviations from the mean for each asset.

        Args:
            data (pd.Series): Mapping from asset names to values.
        """
        return (data-data.mean())/data.std()


# Field class - interface for users to specify when adding a Field to a backtest
class Field:
    def __init__(self, params: Dict[str, Any]):
        self.__check_params(params)

        self.field_op_input = params.copy()
        del self.field_op_input[FIELD_OPERATION_KW] # remove parameter stating the FieldOp

        # Set attributes of the field
        for key in params:
            setattr(self, key, params[key])

    def __check_params(self, params: Dict[str, Any]):
        """Ensure that there are no problems with the parameters given by the user.

        Args:
            params (Dict[str, Any]): Map from parameter name to value. All parameters should be
            arguments to the specified FieldOp, EXCEPT for the FieldOp itself. For example, if 
            this Field represents a 15 day simple moving average over Open prices, then the user
            would have params look something like the following: 
            params={
                'field_operation: fields.fields.SMA,
                'dependent_field_id':FieldId('Open'),
                'field_id':FieldId('SMA_Open_15'),
                'window_len':15
            }. Notice the following facts:
            1. IT IS REQUIRED TO SPECIFY 'field_operation'.
            2. All field names MUST be of type FieldId.
            3. We did not provide any extraneous parameters. Doing so will result in error.
            

        Raises:
            ValueError: See error messages for description. Input to this function is very particular.
        """
        # print('PROHIBITED: {}'.format(PROHIBITED_USER_PROVIDED_FIELD_ATTRIBUTES))
        # Ensure that no prohibited attributes were passed by the user.
        for prohibited_field_attribute in PROHIBITED_USER_PROVIDED_FIELD_ATTRIBUTES:
            if prohibited_field_attribute in params:
                raise ValueError('User cannot provide attribute `{}`'.format(prohibited_field_attribute))
        
        unverified_params = set(params.keys())
        
        # print('unverified_params: {}'.format(unverified_params))
        # Get the field_operation specified by the user.
        if FIELD_OPERATION_KW in unverified_params:
            field_operation = params[FIELD_OPERATION_KW]
            unverified_params.remove(FIELD_OPERATION_KW)
            if (not inspect.isclass(field_operation)) \
                or (not issubclass(field_operation, FieldOp)):
                raise ValueError('Expected `field_operation` to be a subclass of {}, but got type {}.'.format(FieldOp, type(field_operation)))
        else:
            raise ValueError('Expected user to provide {} in `params` dict.'.format(FIELD_OPERATION_KW))
        
        # print('unverified_params: {}'.format(unverified_params))

        # print('all user args: {}'.format(get_field_op_user_args(field_operation)))
        # print('optional user args: {}'.format(get_field_op_user_optional_args(field_operation)))
        # print('required args: {}'.format(get_field_op_user_required_args(field_operation)))

        # Check that all of the required field attributes for this operation are in params.
        for required_field_attribute in get_field_op_user_required_args(field_operation):
            if required_field_attribute not in params:
                raise ValueError('Expected user to provide argument `{}`.'.format(required_field_attribute))
            elif (required_field_attribute == FIELD_ID_KW) and (not isinstance(params[FIELD_ID_KW], FieldId)):
                raise ValueError('Expected `{}` to be of type {}, but it was of type {}. '.format(FIELD_ID_KW, FieldId, type(params[FIELD_ID_KW])) +
                    'Consider initializing an engine.engine_utils.FieldId object with the object you passed to params[`{}`].'.format(FIELD_ID_KW))
            elif (required_field_attribute == DEP_FIELD_ID_KW) and (not isinstance(params[DEP_FIELD_ID_KW], FieldId)):
                raise ValueError('Expected `{}` to be of type {}, but it was of type {}. '.format(DEP_FIELD_ID_KW, FieldId, type(params[DEP_FIELD_ID_KW])) +
                    'Consider initializing an engine.engine_utils.FieldId object with the object you passed to params[`{}`].'.format(DEP_FIELD_ID_KW))
            
            unverified_params.remove(required_field_attribute)
            # print('unverified_params: {}'.format(unverified_params))
        
        # Check that all other parameters passed by user are used for this field.
        optional_field_attributes = set(get_field_op_user_optional_args(field_operation))
        for user_param in unverified_params:
            if user_param not in optional_field_attributes:
                raise ValueError('Received key `{}` in `params`, but the only parameters accepted by {} are: {}.'.format(
                    user_param, field_operation, get_field_op_user_args(field_operation)
                ))
        
        return

