# Next Steps

## Add Orders
### General Info
Simply put, the backtesting system is not complete until this is in place. A lot of the utility of this program comes from the fact that we should be able to use orders similarly to real life. However, this step may need to introduce some more logic into the backbone of `Strategy`.

### Scope
This first version will __only__ consider equities, since this is where my experience lays. Furthermore, it will operate on bar data. All data about the previous bar is received directly after the start of the current bar.

### Data-to-Action Pipeline Explanation
For example, if we have minute-level data, and there is a 5 second delay on getting data from the brokerage, then the OHLCV bar for an asset `2020-06-22 10:00` would be received at `2020-06-22 11:05`. This is based on a `bar_finish->observation->calculation->action` model. In practice, for daily equity price data, this would entail receiving data right after each trading day, then determining an action to take the next day.

There is __not__ currently a feature for taking into account data at the open of a bar. This would require an interface refactoring, since `Engine`'s interface for adding a bar entails adding all of the bar's data. This may not be a huge deal, but it may add challenging corner cases and obscure the code organization. Thus, if this is an issue, it may be better to transition to higher-granularity data (e.g. moving from day-level to minute-level data), and just take action on relatively fewer bars.

### Important Q & A

#### Q: How do we account for profit and loss?
A: The general gist is that we will add a property to the `Strategy` object that
allows us to keep track of our positions. There are a few ways that we could
actually do it. Perhaps what's most important is the question "what makes the
development experience the easiest?". I believe it would be nice to never have
to deal directly with updating the portfolio as a developer, but instead automate
that step when the strategy is running.

#### Q: How do we provide options to the backtest that handle slippage, transaction cost, and capital?
A: There will be an abstract type called `AbstractBrokerOptions` that __must__ contain all basic info about the brokerage (e.g. initial capital, slippage model, and transaction cost model). Then certain concrete types can implement this interface, and also add other options for the particular asset type. For now, we only will have the basics wrapped in an `EquityBrokerOptions` compound type.


## Add Optimization and Different Sampling Techniques
1. Use a train-validation-test style to organize a training, optimization, then testing step. This is particularly important if ML is to be used.
2. Suppose we are interested in seeing how a strategy performs over many 2-week intervals. This is pretty common, right? Making a system that partitions the datasets and then performs sub-tests on each partition (e.g. partitions a year of data into 26 2-week intervals). This form of testing has the following perks:
  1. It allows for a tighter confidence interval around performance. In general, we aren't trying to find a strategy that will perform incredibly over a 5 year period. While that would be nice, there just isn't enough data to form a solid confidence interval around how this algo would perform when deployed (you only have probably one relevant 5-year sample). Thus, it is clear that there is a trade-off between long-term testing and test confidence. That is, if a test is longer, then we cannot partition our data into as many sub-tests, and thus cannot form a confidence interval for our mean performance (or do any analysis of our sub-test results distribution of outcomes).
  2. Speed. Since all of the sub-tests are run independently of each other (and each would presumably take some time), we could run them in parallel. For example, if you have 8 CPU cores, you may be able to run the tests in just over 1/8 the time. That would be nice!
  3. Easy integration with optimization. In the process of making this feature, we would also create generic code for partitioning a dataset by `DateTime`. Once this is in place, we can seamlessly use the partitioning functionality to make a `train-validation-test` partitioning of our dataset.
