module EngineTest
using Random

function enginetest()

  # Make a backtest object
  nbarstostore = 1_000
  assetids = [AssetId("AAPL"), AssetId("MSFT"), AssetId("TSLA")]
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
      AssetId("AAPL") => Dict(FieldId("Open") => rand_(1.0*i), FieldId("Close") => rand_(1.2*i)),
      AssetId("MSFT") => Dict(FieldId("Open") => rand_(2.0*i), FieldId("Close") => rand_(2.5*i)),
      AssetId("TSLA") => Dict(FieldId("Open") => rand_(3.0*i), FieldId("Close") => rand_(2.5*i))
    ) for i in 1:nbarstorun
  ]
  # println(allbars)
  # println()
  # println(allbars[6][AssetId("TSLA")][FieldId("Open")])

  # Make fields
  fields = Vector([
    Open(FieldId("Open")),
    Close(FieldId("Close")),
    SMA(FieldId("SMA-Open-2"), FieldId("Open"), 2),
    SMA(FieldId("SMA-Close-3"), FieldId("Close"), 3),
    # ZScore(FieldId("ZScore-[SMA-Open-2]"), FieldId("SMA-Open-2")),
    # # ZScore(FieldId("ZScore-SMA-Close-3"), FieldId("SMA-Close-3")),
    # SMA(FieldId("SMA-[ZScore-[SMA-Open-2]]-3"), FieldId("ZScore-[SMA-Open-2]"), 3)
  ])
  # print("Fields: ")
  # println(fields)

  addfields!(lattice, fields)

  # print("Dict afterward: ")
  # println(lattice.windowdependentfields)


  # Feed bars into engine
  # (for benchmarking purposes) add first bar separately so that compile time is not included in the benchmark
  newbar!(lattice, allbars[1]);

  @time begin
  for barindex in 2:length(allbars)
    newbar!(lattice, allbars[barindex])
  end end

  nbarstoprint = 2
  for i in (lattice.numbarsstored-nbarstoprint+1):lattice.numbarsstored
    println(lattice.recentbars[i])
  end
end
end
