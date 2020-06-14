# Ideation

+ Data input
    + There are two approaches.
        1. Only the necessary amount of data is loaded in at a time
            + Pros:
                + Lower memory footprint (meaning more scalability)
                + Realistic of how an algo would operate on-line
            - Cons
                - Slow if implemented with File I/O
                - More difficult to implement File I/O
                - **Very** difficult/error-prone to handle handoff for moving window calculations
        2. All data is loaded in at the initialization of the backtest.
            + Pros
                + See cons of (1)
            - Cons
                - See pros of (1)
    + Version 1 of this back testing tool will use option 2, since it is easier to implement and it will
    allow for faster backtests. Keeping in mind the intent of the backtester (rapid experimentation),
    this tool's benefits do not outweigh its detriments (namely the difficulty of implementation and
    slower runtime).
    + Given this decision, the input to the backtester will be a multi-index DataFrame. The 0th level index will be the datetime, and the 1st level index will be the asset identifier.

+ System is event-based
    + Keep an event queue
        + Will be implemeneted in such a way that the backtester 'pushes' an Event object; Event objects MUST have an exec_time attribute, which states when the event is to be executed.
        This will mean that the time for insertion is log(n), where n=number of events already in the queue. This should be quite minimal; the number of events on the event queue should roughly reset at the end of each bar. This is more likely to be the case since
        there will __not__ be "execute after n bars" orders; that logic must be implemented
        outside of the event queue.
        + Let us consider the case where there are 10,000 assets, and each asset has 10
        events pushed to the event queue each bar. Then there are 100,000 events on the
        event queue at most (this is an upper bound, since some events may expire before
        other events are generated). Thus, the amount of time to insert the last event will
        be < 14 steps, thus there will be < 1.4 million steps taking place. This may seem like
        a lot, but keep in mind that (a) this number of events per bar is absurdly high, (b)
        the memory footprint of 10,000 assets of data is far too high for any significant number
        of bars of backtesting (see data input design decision above), so this should really never become a limiting part of this pipeline. 
    

+ System supports cross-sectional analysis, wherein you can roundup signals and compare them across multiple assets (maybe).
    + How will this be implemented? Well, it really shouldn't be that complicated. We just keep a multiindex of all the relevant data, and
    we add indicators as columns.
    + 