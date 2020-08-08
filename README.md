# Backtest.jl
![CI](https://github.com/maxholloway/backtest/workflows/CI/badge.svg?branch=master)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://maxholloway.github.io/Backtest.jl/dev/)

A very simple event-based backtesting platform.

## Background
The aim of this project is to have a straightforward strategy for testing equity trading strategies on historical data. Specifically, we aim to satisfy the following properties here:
1. Testing strategies that use "line" data (data across multiple historical bars for a particular asset) and also "cross-sectional" data (data for a single bar, but multiple assets).
2. Fast testing.
3. Simple API.
4. Extendability.

Any shortcomings of the above goals are a failure of development, and should be raised in this repository's "issues" section.

## Usage

### Downloading the code
This package is not (yet) in Julia's standard registry. Thus, a simple way to obtain this data would be to clone this repo.
```
git clone "https://github.com/maxholloway/Backtest.jl/""
```

### Running tests
```
> cd PATH/TO/REPO/Backtest.jl
> julia # open up julia REPL

# press "]" to enter the package menu

> activate .
> test
```
Currently this repository is only tested on Julia `1.0`, `1.4`, and the Julia `nightly` build in the CI/CD pipeline. If tests fail on your machine, please report this in the [issues](https://github.com/maxholloway/Backtest.jl/issues) section.

### Getting Started
To get started, it's recommended that you walkthrough the GettingStarted jupyter notebook (located in the `examples/` folder). This provides a thorough explanation of the framework interface.

### Development Guidelines
This project is in its infancy! Contact me by email if you are interested in contributing, and we can sync to discuss. 

Email: maxwellpearmanholloway@gmail.com
