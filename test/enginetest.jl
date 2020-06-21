module EngineTest
using Random
using Engine: CalcLattice
using ConcreteFields: Open, Close, SMA, ZScore
function enginetest()

  # Make a backtest object
  nbarstostore = 43_200
  assetids = ["AAPL", "MSFT", "TSLA"]
  lattice = CalcLattice(nbarstostore, assetids)

  function rand_(base::Number)
    SEED = 1234
    rng = MersenneTwister() # Optional: include SEED for reproducibility
    result = base*(1+randn(rng))
    return result
  end

  # Make data
  nbarstorun = max(nbarstostore, 1000)
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
  # newbar!(lattice, allbars[1]);

  @time begin
  for barindex in 1:length(allbars)
    newbar!(lattice, allbars[barindex])
  end end

  nbarstoprint = 2
  for i in (lattice.numbarsstored-nbarstoprint+1):lattice.numbarsstored
    println(lattice.recentbars[i])
  end
end
end
