# Backtest Documentation

```@meta
CurrentModule = Backtest
```

## Intent
`Backtest.jl` exists in order to provide a straightforward interface for
performing backtests in Julia. Moreover, I (Max Holloway) really like some of
the ideas from the python framework `Backtrader`, and I wanted to make my own
(better, simpler) version of it in Julia.

## Core Ideas
In order to get up and running, one only needs to know how to make a `DataReader`
and how to fill in `StrategyOptions`. After that, you can run your backtest!
To add to the backtest, you will need to provide what are called "user-defined
functions". These functions allow one to perform behavior, such as ordering
shares or calculating metrics derived from `FieldOperations`.

## Functions

### Super Important Functions
```@docs
run
StrategyOptions()
order!
```

### Accessor Functions
```@docs
numbarsavailable
data
```

### Other Functions
```@docs
log
```

## Types
### High-Level Types
The following are types that all users must understand when running a backtest.
```@docs
StrategyOptions
Portfolio
```

### Verbosity Types
These types allow users to specify how much verbosity they want in their backtests.
They are ordered here from most to least verbose.
```@docs
AbstractVerbosity
INFO
TRANSACTIONS
WARNING
NOVERBOSITY
```

### Low-Level Types
The following are types that users should never have to access directly.
```@docs
Strategy
```
Feel free to reach out if you have any questions!
