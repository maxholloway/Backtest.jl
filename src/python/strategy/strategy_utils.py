from typing import Dict, List, Any
import datetime as dt
from engine.engine import AssetId

class NoDataReadersException(Exception):
    def __init__(self):
        super().__init__('There are no DataReader objects added to the backtest. Use the `BackTest.add_data` method to add more data sources.')

class InconsistentBarTimesException(Exception):
    def __init__(self, times_seen):
        super().__init__(
            f'When loading bars from DataReaders, there was an inconsistency in bar intervals. The following times were seen: {times_seen}.')


class FieldComputationLatencyException(Exception):
    def __init__(self, computation_start_time, computation_end_time, allotted_computation_time):
        super().__init__(f'Took too long to compute this bar\'s fields. Computation began at {computation_start_time}, and ended at {computation_end_time}, '+
            f'taking a total amount of time of {computation_end_time-computation_start_time}. However, the allotted computation time is {allotted_computation_time}.'
        )


class DictList:
    def __init__(self):
        self.__data: Dict[Any, List] = {}

    def insert(self, k, v):
        if k not in self.__data:
            self.__data[k] = []
        self.__data[k].append(v)

    def get(self, k):
        return self.__data[k]

    def __repr__(self):
        return repr(self.__data)

    def __str__(self):
        return str(self.__data)

    def __len__(self):
        return len(self.__data)