module test

using Random
using Dates
using BenchmarkTools: @benchmark
using Ids: AssetId
using Engine: CalcLattice, addfields!, newbar!
using ConcreteFields: Open, High, Low, Close, Volume, SMA, ZScore, Rank, Returns, LogReturns
using Events: FieldCompletedProcessingEvent, AbstractOrderEvent
using DataReaders: InMemoryDataReader
using Orders: MarketOrder, LimitOrder
using Backtest: Strategy, StrategyOptions, run, order!, log, INFO, TRANSACTIONS
using Utils: crossover, crossunder


function enginetest()

  # Make a backtest object
  nbarstostore = 5
  assetids = ["AAPL", "MSFT", "TSLA"]
  lattice = CalcLattice(nbarstostore, assetids)

  function rand_(base::Number)
    SEED = 1234
    rng = MersenneTwister() # Optional: include SEED for reproducibility
    result = base*(1+randn(rng))
    return result
  end

  # Make data
  nbarstorun = max(nbarstostore, 120_960)
  allbars = [
    Dict(
      "AAPL" => Dict("Open" => rand_(1.0*i), "Close" => rand_(1.2*i)),
      "MSFT" => Dict("Open" => rand_(2.0*i), "Close" => rand_(2.5*i)),
      "TSLA" => Dict("Open" => rand_(3.0*i), "Close" => rand_(2.5*i))
    ) for i in 1:nbarstorun
  ]
  # println(allbars)
  # println()
  # println(allbars[6][AssetId("TSLA")][FieldId("Open")])

  # Make fields
  fieldoperations = Vector([
    Open("Open"),
    Close("Close"),
    SMA("SMA2-Open", "Open", 2),
    SMA("SMA3-Close", "Close", 3),
    ZScore("ZScore-Open", "Open")
  ])
  # print("Fields: ")
  # println(fields)

  addfields!(lattice, fieldoperations)

  # print("Dict afterward: ")
  # println(lattice.windowdependentfields)


  # Feed bars into engine
  # (for benchmarking purposes) add first bar separately so that compile time is not included in the benchmark
  newbar!(lattice, allbars[1]);

  @time begin
  for barindex in 2:length(allbars)
    newbar!(lattice, allbars[barindex])
  end end

  nbarstoprint = 0
  nbars = length(lattice.recentbars)
  for i in (nbars-nbarstoprint+1):nbars
    println(lattice.recentbars[i])
  end
end

function getexamplecryptodatareader(symbol::String)
  basepath = string("../../data/crypto/", symbol, "/individual_csvs")
  daysofmonth = [lpad(i, 2, "0") for i=1:30]
  dayofmonthtopath = (dom -> string(basepath, "/2019-06-", dom, ".csv"))
  sources = [dayofmonthtopath(dom) for dom in daysofmonth]
  return InMemoryDataReader(symbol, sources, datetimecol="Opened")
end

function datareadertest()
  # Test that this doesn't error out.
  getexamplecryptodatareader("BTCUSDT")
  getexamplecryptodatareader("LTCUSDT")
  getexamplecryptodatareader("ETHUSDT")
end

function bttest()
  ## Make the data readers ##
  assetids = ["BTCUSDT", "LTCUSDT", "ETHUSDT"]
  datareaders = Dict{AssetId, InMemoryDataReader}()
  for assetid in assetids
    datareaders[assetid] = getexamplecryptodatareader(assetid)
  end

  ## Make the field operations ##
  (dt, o, h, l, c, v) = ("Opened", "Open", "High", "Low", "Close", "Volume")
  fieldoperations = [
    SMA("SMA30-Close", c, 30),
    SMA("SMA60-Close", c, 60),
    # ZScore("ZScore-Open", o),
    # Rank("Rank-Close", c),
    # Returns("Returns-Close", c),
    # Returns("Returns-Close-3", c, 3),
    # LogReturns("LogReturns-Close", c),
    # LogReturns("LogReturns-Close-3", c, 3),
  ]

  function ondata(strat::Strategy, event::FieldCompletedProcessingEvent)
    # order!(strat, MarketOrder("LTCUSDT", 1))
    # order!(strat, LimitOrder("LTCUSDT", -1, 10))
    fast, slow = "SMA30-Close", "SMA60-Close"
    if crossover(strat, "LTCUSDT", fast, slow)
      order!(strat, MarketOrder("LTCUSDT", 5))
    elseif crossunder(strat, "LTCUSDT", fast, slow)
      order!(strat, MarketOrder("LTCUSDT", -5))
    end

  end
  function onorder(strat::Strategy, event::ET) where {ET<:AbstractOrderEvent}
  end
  stratoptions = StrategyOptions(
    datareaders=datareaders,
    fieldoperations=fieldoperations,
    numlookbackbars=65,
    start=Dates.DateTime(2019, 06, 02, 0, 0),
    endtime=Dates.DateTime(2019, 06, 3, 0, 0),
    barsize=Dates.Minute(1),
    verbosity=TRANSACTIONS,
    datadelay=Dates.Second(5),
    messagelatency=Dates.Second(3),
    datetimecol=dt,
    opencol=o,
    highcol=h,
    lowcol=l,
    closecol=c,
    volumecol=v,
    ondataevent=ondata,
    onorderevent=onorder,
    principal=1_000
  )

  ## Run the backtest ##
  @time run(stratoptions)

end

end
