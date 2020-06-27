module test

using Random
using Dates
using Ids: AssetId
using Engine: CalcLattice, addfields!, newbar!
using ConcreteFields: Open, High, Low, Close, Volume, SMA, ZScore, Rank
using Events: FieldCompletedProcessingEvent, AbstractOrderEvent
using DataReaders: InMemoryDataReader
using Backtest
using Orders: MarketOrder, LimitOrder


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
  getexamplecryptodatareader("BTCUSDT")
  getexamplecryptodatareader("LTCUSDT")
  getexamplecryptodatareader("ETHUSDT")

  # should yield a large dataframe with appended sub dataframes
end

function bttest()
  ## Make the data readers ##
  assetids = ["BTCUSDT", "LTCUSDT", "ETHUSDT"]
  datareaders = Dict{AssetId, InMemoryDataReader}()
  for assetid in assetids
    datareaders[assetid] = getexamplecryptodatareader(assetid)
  end

  ## Make the field operations ##
  (o, h, l, c, v) = ("Open", "High", "Low", "Close", "Volume")
  fieldoperations = Vector([
    Open(o),
    High(h),
    Low(l),
    Close(c),
    Volume(v),
    SMA("SMA2-Open", o, 2),
    SMA("SMA3-Close", c, 3),
    ZScore("ZScore-Open", o),
    Rank("Rank-Close", c)
  ])

  ## Set strategy options (doesn't have to be this verbose irl)##
  function ondata(strat::Backtest.Strategy, event::FieldCompletedProcessingEvent)
    # Backtest.log(strat, "just received data for the previous bar; placing an order of 1 litecoin", Backtest.NOVERBOSITY)
    # Backtest.order!(strat, MarketOrder("LTCUSDT", 1))
    Backtest.order!(strat, LimitOrder("LTCUSDT", -1, 10))
  end
  function onorder(strat::Backtest.Strategy, event::ET) where {ET<:AbstractOrderEvent}
    println(event)
    println(strat.portfolio)
  end
  stratoptions = Backtest.StrategyOptions(
    datareaders=datareaders,
    fieldoperations=fieldoperations,
    numlookbackbars=-1,
    start=Dates.DateTime(2019, 06, 02, 0, 0),
    endtime=Dates.DateTime(2019, 06, 02, 0, 3),
    barsize=Dates.Minute(1),
    verbosity=Backtest.INFO,
    datadelay=Dates.Second(5),
    orderackdelay=Dates.Second(3),
    datetimecol="Opened",
    opencol="Open",
    highcol="High",
    lowcol="Low",
    closecol="Close",
    volumecol="Volume",
    ondataevent=ondata,
    onorderevent=onorder,
    principal=1000
  )

  ## Run the backtest ##
  @time begin
  Backtest.run(stratoptions)
  end

end

end
