using Documenter, Backtest

makedocs(
    sitename="Backtest Documentation",
    modules=[Backtest]
)

deploydocs(
    repo = "github.com/maxholloway/backtest.git",
)
