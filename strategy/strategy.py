from typing import Dict, Iterable, Set, List, Any
import datetime as dt
import pandas as pd
from abc import ABC, abstractmethod
from engine.engine import CalcLattice
from engine.fields.fields import Field
from datareader.datareader import DataReaderBase
from engine.engine_utils import AssetId, FieldId, StaticDAGException
from strategy.events import EventBase, NewBarEvent, FieldProcessingCompletedEvent, OrderEvent
from strategy.strategy_utils import FieldComputationLatencyException

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

    def push(self, event: EventBase): # TODO: modify this to simply insert the new event in the proper index (O(log(n))), instead of sorting (>=O(N))
        self.series[event.time] = event
        self.series.sort_index(inplace=True, kind='heapsort') # should have ~O(N) runtime (could get to log_2(N) if implemented by hand)
        return

    def empty(self):
        return (self.series.size == 0)
    
    def __str__(self):
        return str(self.series)


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
    def __init__(self, barsize: dt.timedelta=dt.timedelta(days=1), open_delay_seconds: float=0, 
        num_bars_to_store: int=100, allotted_computation_time: float=None, verbosity: int = VerbosityLevel.NONE):
        """Options for configuring a backtest.

        Args:
            barsize (dt.timedelta, optional): How much time does one bar represent? This is calculated as open_{i+1} - open_{i}. Defaults to dt.timedelta(days=1).
            open_delay_seconds (float, optional): Amount of time (in seconds) after the beginning of a bar before the previous bar's data is available. For daily rebalancing this should be 0. Defaults to 0.
            verbosity (int, optional): How verbose the backtest should be. Defaults to VerbosityLevel.NONE.
        """
        
        self.barsize = barsize
        self.open_delay_seconds = open_delay_seconds
        self.num_bars_to_store = num_bars_to_store
        self.allotted_computation_time = allotted_computation_time if allotted_computation_time else self.barsize
        self.verbosity = verbosity


    
class Backtest(ABC):
    """Base class providing infrastructure for running a backtest. Handles order placement,
    data access, and portfolio tracking in an event-based fashion.
    """

    def __init__(self, start: dt.datetime, end: dt.datetime, options: BacktestOptions=BacktestOptions()):
        self.start_time = start
        self.end_time = end
        self.options = options
        
        self.__can_run = True # True iff the `run` function has not been called yet; we cannot run the same Backtest twice, since `run` modifies state.
        
        # Queue allowing for events to be added and read at execution time.
        self.events = EventQueue()
        
        # Attributes initialized from invocations of `add_data`
        self.__asset_ids = set()
        self.__datareaders = []

        # Attributes initialized at the beginning of `run` through the `__prepare_lattice` function.
        self.__calclattice: CalcLattice = None
        self.__fields: List[Field] = []

        # Attributes utilized throughout the backtest
        self.cur_time = start
        self.__cur_bar_index = -1 # which bar we're currently on; increments each time we 

        return

    ## Utility methods ##
    def __log(self, message: str, verbosity_level: int):
        """
        In general, use a high verbosity level if the message should only be printed when a user wants a lot of verbosity.
        """
        if verbosity_level <= self.options.verbosity:
            print('{} ~~~~~~~~ {}'.format(self.cur_time, message))
        return
    
    def time(self) -> dt.datetime:
        return self.cur_time
    
    def __get_cur_bar_start_time(self) -> dt.datetime:
        return (self.start_time + self.__cur_bar_index * self.options.barsize)
        
    def __get_next_bar_start_time(self) -> dt.datetime:
        return (self.__get_cur_bar_start_time() + self.options.barsize)

    def __next_bar_exists(self):
        return (self.__get_next_bar_start_time() < self.end_time)
    
    ## Adding data ##
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

    ## Adding fields ##
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
         
    ## Running back test ##
    def __prepare_lattice(self) -> None:
        """Initialize `self.__calclattice`.
        """
        self.__calclattice = CalcLattice(self.options.num_bars_to_store, self.__asset_ids)
        for field in self.__fields:
            self.__calclattice.add_field(field)
        pass
    
    def __load_genesis_data(self) -> float: # TODO: implement multiprocessing OR asyncio task logic to load all asset bars in parallel
        # for each of the assets that we're working with, load their input bars (i.e. the bars that would be streamed each time interval, such as OHLCV)
        # return [num successfully loaded assets]/[total num assets] (e.g. if 3/4 of the assets were loaded correctly, return .75)
        # NOTE: THIS MODIFIES STATE BY ADDING BARS TO `events`!!
        num_failed_bar_loads = 0
        asset_to_genesis_field_to_data: Dict[AssetId, Dict[FieldId, Any]] = {}
        for datareader in self.__datareaders:
            try:
                asset_to_genesis_field_to_data[datareader.asset_id] = datareader.get_next_bar()
            except Exception as ex:
                self.__log('Got the following exception while getting genesis data for {}:\n'.format(datareader.asset_id, ex), VerbosityLevel.LOW)
                num_failed_bar_loads += 1
        correctly_classified_proportion = 1 - (num_failed_bar_loads)/len(self.__datareaders)
        
        return (correctly_classified_proportion, asset_to_genesis_field_to_data)        
        
    def run(self) -> None:

        # Check that a backtest has not already been run
        if self.__can_run:
            self.__can_run = False
        else:
            raise Exception("Backtest instances can only be run once. `run` was invoked more than once.")

        self.__prepare_lattice()

        while True:
            if self.__next_bar_exists(): # check if it's possible to start the next bar
                proportion_of_correctly_loaded_asset_data, asset_to_genesis_field_to_data =  self.__load_genesis_data()
                if (proportion_of_correctly_loaded_asset_data == 1.0):
                    self.__run_next_bar(asset_to_genesis_field_to_data)
                else:
                    self.__log('Only {}% of the genesis assets loaded correctly.'.format(proportion_of_correctly_loaded_asset_data*100) + \
                        ' Terminating backtest.', VerbosityLevel.MEDIUM)
                    break
            else:
                self.__log('Current time is {}, so backtest is complete.'.format(self.cur_time), VerbosityLevel.MEDIUM)
                break         
        return

    def __run_next_bar(self, asset_to_genesis_field_to_data: Dict[AssetId, Dict[FieldId, Any]]) -> None:
        # 1. Update internal attributes to reflect that it's now a new bar.
        # 2. Push a NewBarEvent.

        # Update object variables for the transition to the next bar
        self.__cur_bar_index += 1 # NOTE: THIS IS THE ONLY LOCATION THAT IS PERMITTED TO MODIFY __cur_bar_index
        self.cur_time = self.__get_cur_bar_start_time()

        # Push an event to signal that the next bar is here! 
        # NOTE: there is no issue with this event being pushed at any point in the real world; 
        # we will still be able to begin the bar in this manner. For example, if we get data
        # before we increment the variables, then the data will simply not be taken into account
        # until the incrementing has taken place. Since the time necessary for starting up the
        # next bar is minimal, this should not be an issue
        self.events.push(
            NewBarEvent(
                time = self.cur_time + dt.timedelta(seconds=self.options.open_delay_seconds),
                genesis_data = asset_to_genesis_field_to_data
            )
        )

        while True:
            if self.events.empty():
                self.__log('Finished step due to empty queue.', VerbosityLevel.HIGH)
                break
            elif self.events.peek().time > self.__get_next_bar_start_time():
                self.__log('Finished step due to an event being past the end time. It will remain on the queue if there is a next step.', VerbosityLevel.HIGH)
                break
            else:
                event = self.events.pop() # pop an event off of the event queue
                self.__log('Processing {} event.'.format(type(event)), VerbosityLevel.HIGH)
                self.__process_event(event)
        return

    ## Processing Events ##    
    def __process_event(self, event: EventBase):
        if event.time > self.__get_next_bar_start_time():
            raise Exception('Implementation error: an event that is supposed to occur in a future bar occurred in this bar. This should be impossible.' +
                'Ensure that `__process_event` is only invoked by `__run_next_bar`.'
            )

        self.cur_time = event.time
        
        # Process different types of events. NOTE: Beware of inheritance here. isinstance(grandchild_object, GrandParentClass) will return True, so the furthest derived classes should be checked first.
        if isinstance(event, NewBarEvent): 
            self.__on_new_bar_event(event)
        elif isinstance(event, FieldProcessingCompletedEvent):
            self.on_data_event(event)
        elif isinstance(event, OrderEvent):
            self.on_order_event(event)
        else:
            raise ValueError('Unknown event type!')
        return

    def __on_new_bar_event(self, event: NewBarEvent) -> None:
        """When a new bar of genesis data comes in, we compute the
        necessary derived fields, then push a FieldProcessingCompletedEvent
        onto the event queue.

        Args:
            event (NewBarEvent): Event with data that presumably would come from an
                outside source, such as a broker or exchange. However, there are no
                constraints on what data is passed; this data could just as easily
                come from the twitter API, or from some other streaming service.
        """
        new_bar_genesis_data: Dict[AssetId, Dict[FieldId, Any]] = event.genesis_data

        real_life_start_time = dt.datetime.now()
        self.__calclattice.new_bar(new_bar_genesis_data) # TODO: make this call async, add a timeout flag
        real_life_end_time = dt.datetime.now()
        
        # Check if it took too long
        data_processing_time_to_completion = real_life_end_time-real_life_start_time
        if (data_processing_time_to_completion > self.options.allotted_computation_time):
            raise FieldComputationLatencyException(self.cur_time, self.cur_time+data_processing_time_to_completion, self.options.allotted_computation_time)

        self.events.push(
            FieldProcessingCompletedEvent(
                self.cur_time + data_processing_time_to_completion # account for the extra time that it takes to perform the computation
            ))
        return

    @abstractmethod
    def on_data_event(self, event: FieldProcessingCompletedEvent): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    @abstractmethod
    def on_order_event(self, event: OrderEvent): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    


if __name__ == '__main__':
    
    pass