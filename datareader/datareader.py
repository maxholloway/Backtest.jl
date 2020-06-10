from abc import ABC, abstractmethod
from typing import Dict, Any, List, Union, Callable
from types import FunctionType
import datetime as dt
import pandas as pd
from engine.engine import AssetId, FieldId
from datareader.datareader_utils import NoMoreDataAvailableException

class Bar:
    def __init__(self, time: dt.datetime, data: Dict[FieldId, Any]):
        self.time = time
        self.data = data


DEFAULT_READ_CSV_OPTIONS = {
    'delimiter': ',',
    'index_col': 'datetime'
}

class DataReaderOptions:
    def __init__(self, read_csv_options: Dict[str, Any], field_name_to_field_id: Dict[str, FieldId]):
        self.read_csv_options = read_csv_options
        self.field_name_to_field_id = field_name_to_field_id
        

class DataReaderBase:
    """Class used for reading data from CSV files.
    The way that this is executed is dependent on the
    implementation. Each implementation must pay special
    attention to the latency vs. memory overhead issue.
    If one reads each bar using File I/O, this has minimal
    space overhead but maximal latency. Alternatively, a
    DataReader that stores all of the files' data has significant
    space overhead, but minimal access latency.
    """
    @abstractmethod
    def __init__(self):
        pass

    @abstractmethod
    def get_next_bar(self) -> Bar:
        pass

    pass

class DataReader(DataReaderBase):
    """Class used for reading data from CSV files.
    The class keeps a simple cache of the current file's data
    in memory, but does not store all of the files' data. This
    DataReader is the `momma bear` solution to the latency/space
    trade-off outlined in the DataReaderBase docstring, since
    it combines medium space complexity (storing a single DataFrame)
    with medium latency (only doing File I/O once for each file).
    """
    
    def __init__(self, asset_id: str, data_paths: List[str], reader_options):
        if not data_paths:
            raise ValueError('There must be at least one path in order to access data.')

        self.asset_id: AssetId = AssetId(asset_id)
        self.data_paths = data_paths
        self.reader_options = reader_options
        
        self.__cur_file_index = -1 # index in `self.data_paths` where data should be accessed
        self.__cur_data_index = -1 # index in `self.__cur_data` where the bar data can be accessed
        self.__cur_data = None
        self.__genesis_field_ids = None
        self.__load_next_file_path()
        
    def __load_next_file_path(self):
        self.__cur_file_index += 1
        self.__cur_data = pd.read_csv(self.data_paths[self.__cur_file_index], **self.reader_options.read_csv_options)
        if len(self.__cur_data) == 0:
            raise ValueError('Unable to extract bar data from {}; 0 bars were parsed.'.format(self.data_paths[self.__cur_file_index]))
        self.__convert_cols_to_field_ids()
    
    def __convert_cols_to_field_ids(self):
        """All of 

        Raises:
            ValueError: [description]
            ValueError: [description]
        """
        schema = self.reader_options.field_name_to_field_id
        if isinstance(schema, dict):
            self.__cur_data.columns = [schema[col] for col in self.__cur_data.columns]
        elif type(schema) is FunctionType:
            self.__cur_data.columns = [schema(col) for col in self.__cur_data.columns]
        else:
            raise ValueError(f'Unknown schema type `{type(schema)}`.')

        # Check that after reading the new data, it still has the same column names (and thus the same genesis fields)
        if self.__genesis_field_ids == None: # if this is the first conversion of csv column names
            self.__genesis_field_ids = set(self.__cur_data.columns)
        elif self.__genesis_field_ids != set(self.__cur_data.columns):
            raise ValueError(f'Column names changed when loading a new file. Expected columns to be {self.__genesis_field_ids},' +\
                f'but they were actually {set(self.__cur_data.columns)}. Ensure that all input files for a particular asset have the same naming scheme.')

    def __more_data_files_exist(self):
        return (self.__cur_file_index+1) < len(self.data_paths)
    
    def get_cur_bar_pd(self) -> pd.Series:
        """Returns the current bar of data.

        Raises:
            Exception: Raised when there are no more files from which data can be read.

        Returns:
            pd.Series: The next bar of data.
        """
        if self.__cur_data_index >= len(self.__cur_data): # we need to load more data!
            if self.__more_data_files_exist():
                self.__load_next_file_path()
                self.__cur_data_index = 0
            else:
                raise NoMoreDataAvailableException()
        
        return self.__cur_data.iloc[self.__cur_data_index]

    def get_next_bar_pd(self) -> pd.Series:
        """Returns the next bar of data.

        Raises:
            Exception: Raised when there are no more files from which data can be read.

        Returns:
            pd.Series: The next bar of data.
        """
        self.__cur_data_index += 1
        return self.get_cur_bar_pd()
        
            
    def get_cur_bar(self) -> Bar:
        data = self.get_cur_bar_pd()
        return Bar(data.name, dict(data))
    
    def get_next_bar(self) -> Bar:
        data = self.get_next_bar_pd()
        return Bar(data.name, dict(data))

    
    

