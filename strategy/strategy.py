from typing import Iterable, Set
import datetime as dt
import pandas as pd
from abc import ABC, abstractmethod
from engine.engine import CalcLattice
from engine.fields.fields import Field
from datareader.datareader import DataReaderBase
from engine.engine_utils import AssetId, FieldId, AssetFieldId, StaticDAGException
from strategy.events import NewBarEvent, FieldProcessingCompletedEvent, OrderEvent

class EventQueue:
    
    def __init__(self):
        self.series = pd.Series(dtype=object)

    def peek(self):
        return self.series.iloc[0]

    def pop(self):
        if self.empty():
            raise IndexError('EventQueue is empty; popping is not possible.')
        else:
            return self.series.pop(self.series.index[0]) # remove the top event from the queue

    def push(self, event: Event): # TODO: modify this to simply insert the new event in the proper index (O(log(n))), instead of sorting (>=O(N))
        self.series[event.time] = event
        self.series.sort_index(inplace=True, kind='heapsort') # should have ~O(N) runtime (could get to log_2(N) if implemented by hand)
        return

    def empty(self):
        return (self.series.size == 0)
    
    def __str__(self):
        return str(self.series)

    pass


class VerbosityLevel:
    """
    NONE: log nothing
    LOW:
    MEDIUM:
    HIGH: log everything
    """
    NONE = 0
    LOW = 1
    MEDIUM = 2
    HIGH = 3


class BacktestOptions:
    def __init__(self, barsize: dt.timedelta=dt.timedelta(days=1), open_delay: float=0, 
        num_bars_to_store: int=100, verbosity: int = VerbosityLevel.NONE):
        """Options for configuring a backtest.

        Args:
            barsize (dt.timedelta, optional): How much time does one bar represent? This is calculated as open_{i+1} - open_{i}. Defaults to dt.timedelta(days=1).
            open_delay (float, optional): Amount of time (in seconds) after the beginning of a bar before the previous bar's data is available. For daily rebalancing this should be 0. Defaults to 0.
            verbosity (int, optional): How verbose the backtest should be. Defaults to VerbosityLevel.NONE.
        """
        
        self.barsize = barsize
        self.open_delay_seconds = open_delay
        self.num_bars_to_store = num_bars_to_store
        self.verbosity = verbosity

    pass


class BackTest:
    def __init__(self, start: dt.datetime, end: dt.datetime, options: BacktestOptions=BacktestOptions()):
        self.cur_time = start
        self.end_time = end
        self.options = options
        
        self.__can_run = True # True iff the `run` function has not been called yet; we cannot run the same BackTest twice, since `run` modifies state.
        
        # Queue allowing for events to be added and read at execution time.
        self.events = EventQueue()
        
        # Attributes initialized from invocations of `add_data`
        self.__asset_ids = set()
        self.__datareaders = []

        # Attributes initialized at the beginning of `run` through the `__prepare_lattice` function.
        self.__calclattice: CalcLattice = None
        self.__fields: List[Field] = []

        return
    
    def add_data(self, datareader: DataReaderBase) -> None:
        """Add a DataReader to the backtest. The DataReader is then used to feed 
        data to the backtest at runtime (e.g. OHLCV data). Each asset to be used
        in a backtest has precisely one DataReader associated with it.

        Args:
            datareader (DataReaderBase): See datareader.datreader.DataReaderBase's docstring for details.
        """
        if datareader.asset_id in self.__asset_ids:
            raise ValueError(f'There is aready a DataReader associated with {datareader.asset_id}. There cannot be two data readers for the same asset.')
        
        self.__datareaders.append(datareader)
        return

    def add_field(self, field: Field) -> None:
        """Add a field to the strategy.

        Args:
            field (Field): See engine.fields.Field for details.
        """
        self.__fields.append(field)
        return
    
    def add_fields(self, fields: Iterable[Field]) -> None:
        """Call `add_field` on each of the provided fields.
        If the `fields` iterable is ordered, then the fields will
        be added to the backtest in that order.

        Args:
            fields (Iterable[Field]): Fields to add to the strategy.
        """
        for field in fields: # add each field in sequence
            self.add_field(field)
        return
         
    def __prepare_lattice(self) -> None:
        """Initialize `self.__calclattice`.
        """
        self.__calclattice = CalcLattice(self.options.num_bars_to_store, self.__asset_ids)
        pass
    
    ## Running back test ##
    def run(self):
        if self.__can_run:
            self.__can_run = False
        else:
            raise Exception("Backtest instances can only be run once. `run` was invoked more than once.")

        self.__prepare_lattice()

        prop_genesis_data_loaded = self.load_genesis_data()
        while True: 
            if prop_genesis_data_loaded != 1.0: # (all assets are loaded correctly)
                self.log('Only {}% of the genesis assets loaded correctly. Terminating backtest.'.format(prop_genesis_data_loaded*100), VerbosityLevel.MEDIUM)
                break
            elif (self.cur_time >= self.end_time):
                self.log('Current time is {}, so backtest is complete.'.format(self.cur_time), VerbosityLevel.MEDIUM)
                break
            
            run_step(end=self.cur_time+self.options.barsize)
            prop_genesis_data_loaded = self.load_genesis_data()

                    
        return

    def run_step(self, end: dt.datetime):
        # run until (a) there are no events left to process, or (b) the next event to process is past the time limit
        while True:
            if self.events.empty():
                self.log('Finished step due to empty queue.', VerbosityLevel.HIGH)
                return
            elif self.events.peek().time > end:
                self.log('Finished step due to an event being past the end time. It will remain on the queue if there is a next step.', VerbosityLevel.HIGH)
                return
            else:
                event = self.events.pop() # removes next event from event queue
                self.log('Processing {} event.'.format(event.event_type), VerbosityLevel.HIGH)
                self.process_event(event)
            
        return

    ## Getting Data ##    
    def load_genesis_data(self) -> float: # TODO: implement multiprocessing OR asyncio task logic to load all asset bars in parallel
        # for each of the assets that we're working with, load their input bars (i.e. the bars that would be streamed each time interval, such as OHLCV)
        # return [num successfully loaded assets]/[total num assets] (e.g. if 3/4 of the assets were loaded correctly, return .75)
        # NOTE: THIS MODIFIES STATE BY ADDING BARS TO `events`!!
        num_failed_bar_loads = 0
        asset_to_genesis_field_to_data: Dict[AssetId, Dict[FieldId, Any]] = {}
        for datareader in self.__datareaders:
            try:
                asset_to_genesis_field_to_data[datareader.asset_id] = datareader.get_next_bar()
            except Exception as ex:
                self.log('Got the following exception while getting genesis data for {}:\n'.format(datareader.asset_id, ex), VerbosityLevel.LOW)
                num_failed_bar_loads += 1
        
        self.events.push(
            NewBarEvent(
                time = self.cur_time + dt.timedelta(seconds=self.options.open_delay_seconds), # account for extra time it takes after beginning of bar to get genesis data
                genesis_data = asset_to_genesis_field_to_data
            )
        )
        
        incorrectly_classified_proportion = (num_failed_bar_loads)/len(self.__datareaders)
        return 1 - incorrectly_classified_proportion

    ## Processing Events ##    
    def process_event(self, event: Event): # done for now!
        self.cur_time = event.time
        # custom logic for what to do given certain events
        if isinstance(event, NewBarEvent): 
            on_new_bar_event(self, event)
        elif isinstance(event, FieldProcessingCompletedEvent):
            on_data_event(self, event)
        elif isinstance(event, OrderEvent):
            on_order_event(self, event)
        else:
            raise ValueError('Unknown event type!')
        return

    def on_new_bar_event(self, event: NewBarEvent) -> None:
        new_bar_genesis_data: Dict[AssetId, Dict[FieldId, Any]] = event.genesis_data
        self.__calclattice.new_bar(new_bar_genesis_data)
        return

    
    def on_data_event(self, event: FieldProcessingCompletedEvent): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    def on_order_event(self, event: OrderEvent): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    ## Other methods ##
    def log(self, message: str, verbosity_level: int):
        """
        In general, use a high verbosity level if the message should only be printed when a user wants a lot of verbosity.
        """
        if verbosity_level <= self.options.verbosity:
            print('{} ~~~~~~~~ {}'.format(self.cur_time, message))
        return


if __name__ == '__main__':
    
    pass