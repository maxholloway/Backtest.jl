# Extendability

## Summary
This document explores ways that we can make the backtest interface extendable by users. There is a large problem that arises due to the fact that we cannot exted concrete types (detailed below).

## Problem
We've written the engine! Now all we need to do is write the backtest. In the python implementation, we used a basic backtest class that would be extended by a user (same paradigm as Backtrader). In that version, tons of infrastructure was handled by the base class, and then the child class would inherit all of that behavior. But that's impossible with Julia.

## Solutions

### Solution 1
This solution is perhaps the closest to the python implementation. It involves writing all of the functionality to work on an abstract `strategum` type, then allowing a user to make their own type that is subtypes `strategum`. The first part of this implementation would involve implementing a lot of backend logic that replicates the python code. Then the second part would involve one of two things. Either we would make the user define all of the low level variables with their own concrete type (which obviously isn't optimal), or we make some function that generates a type.

### Solution 2
Define a `BacktestOptions` type that is passed to the constructor of `Backtest`. Some of these options could be functions that are defined by the user. Then, these functions would be accessed from withing `Backtest`'s functions accordingly. This seems to be the most Julian way of approaching this problem. `Backtest` is a type, and part of what defines that type is what it does for `ondata`, etc.


## Reflection
It really looks like solution 2 is significantly better, for a couple reasons. First of all, it eliminates the need for funky type-generating logic. Second, it is more removed from OOP style, which is honestly a good way for me to grow as a programmer. Third, it conveys a very very real idea that all behavior here is just data, and when a user specifies "their own" backtest, that can be equivalently represented as just passing particular arguments to THE backtest. ;)