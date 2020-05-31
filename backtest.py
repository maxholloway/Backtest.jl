from typing import Dict
import datetime as dt
import pandas as pd

class EventType:
    ORDER = 'ORDER'
    DATA = 'OPEN'


class Event:
    def __init__(self, event_type: str, exec_time: dt.datetime, ):
        self.event_type = event_type
        self.exec_time = exec_time
        return
    

class EventQueue:
    
    def __init__(self):
        self.series = pd.Series(dtype=object)

    def peek(self):
        return self.series.iloc[0]

    def pop(self):
        if self.empty():
            raise Exception('EventQueue is empty; popping is not possible.')
        else:
            return self.series.pop(self.series.index[0]) # remove the top event from the queue

    def push(self, event: Event): # TODO: modify this to simply insert the new event in the proper index (O(log(n))), instead of sorting (>=O(N))
        self.series[event.exec_time] = event
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
    def __init__(self, barsize: dt.timedelta=dt.timedelta(days=1), verbosity: int = VerbosityLevel.NONE):
        self.barsize = barsize
        self.verbosity = verbosity
    pass


class BackTest:
    def __init__(self, data: pd.DataFrame, start: dt.datetime, end: dt.datetime, options: BacktestOptions=BacktestOptions()):
        self.data = data
        self.options = options
        self.events = EventQueue()
        self.cur_time = start
        return

    ## Running back test ##
    def run(self):

        while self.load_asset_bars()==1.0: # (all assets are loaded correctly)
            run_step(end=self.cur_time+self.options.barsize)

        return

    def run_step(self, end: dt.datetime): # done for now!
        # run until (a) there are no events left to process, or (b) the next event to process is past the time limit
        while True:
            if self.events.empty():
                self.log('Finished step due to empty queue.', VerbosityLevel.HIGH)
                return
            elif self.events.peek().exec_time > end:
                self.log('Finished step due to an event being past the end time.', VerbosityLevel.HIGH)
                return
            else:
                event = self.events.pop() # removes next event from event queue
                self.log('Processing {} event.'.format(event.event_type))
                self.process_event(event)
            
        return

    ## Getting Data ##
    def load_asset_bar(self, asset_id) -> bool: # TODO: decide how the bars will be read in
        # put an event for the open and the close; 
        # let open be about OPEN_DELAY ms after the start of the minute, to simulate when data would be received,
        # and to differentiate between the last close and the current open
        # returns True if it can load another bar, or False if there are no more bars to load
        # CAUTION: THIS MODIFIES STATE BY ADDING BARS TO `events`!!

        pass

    def load_asset_bars(self) -> float: # TODO: (1) decide where to keep asset names, and (2) implement multiprocessing OR asyncio task logic to load all asset bars in parallel
        # for each of the assets that we're working with, load their bars
        # return [num correctly loaded assets]/[total num assets] (e.g. if half of the assets were loaded correctly, return .5)
        # CAUTION: THIS MODIFIES STATE BY ADDING BARS TO `events`!!
        pass

    ## Processing Events ##    
    def process_event(self, event: Event): # done for now!
        self.cur_time = event.exec_time
        # custom logic for what to do given certain events
        if event.event_type == EventType.DATA:
            process_data_event(self, event)
        elif event.event_type == EventType.ORDER:
            process_order_event(self, event)
        else:
            raise Exception('Unknown event type!')
        return

    def process_data_event(self, event: Event): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    def process_order_event(self, event: Event): # TODO: decide if this is the right level of abstraction for the user to overwrite
        pass

    ## Other methods ##
    def log(self, message: str, verbosity_level: int):
        """
        In general, use a high verbosity level if the message should only be printed when a user wants a lot of verbosity.
        """
        if verbosity_level <= self.options.verbosity:
            print('{} ~~~~~~~~ {}'.format(self.cur_time, message))
        return
