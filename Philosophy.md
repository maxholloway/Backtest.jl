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
    + Version 1 of this back testing tool will use option 1, since it is easier to make and it will
    allow for faster backtests. Keeping in mind the intent of the backtester (rapid experimentation),
    this tool's benefits do not outweigh its detriments (namely the difficulty of implementation and
    slower runtime).
    + Given this decision, the input to the backtester will be 

+ System is event-based
    + Keep an event queue
        + Will be implemeneted in such a way that you insert an kv pair where key is the time of the event, value is the event itself.
        This will mean that the time for insertion is log(n), where n=number of events already in the queue. This should be quite minimal,
        since the number of events inserted at a time should be quite minimal.
    + Methods:
        + on_new_bar
        + on_order_event

+ System supports cross-sectional analysis, wherein you can roundup signals and compare them across multiple assets (maybe).
    + How will this be implemented? Well, it really shouldn't be that complicated. Instead of having a single data source,
    we can work with a mapping from asset to its data upon input to the backtester (or a dataframe with a multiindex).
    + 