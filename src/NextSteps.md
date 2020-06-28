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
