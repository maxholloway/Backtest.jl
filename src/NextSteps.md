# Next Steps

### Important Q & A

#### Q: How do we provide options to the backtest that handle slippage, transaction cost, and capital?
A: There will be an abstract type called `AbstractBrokerOptions` that __must__ contain all basic info about the brokerage (e.g. initial capital, slippage model, and transaction cost model). Then certain concrete types can implement this interface, and also add other options for the particular asset type. For now, we only will have the basics wrapped in an `EquityBrokerOptions` compound type.
