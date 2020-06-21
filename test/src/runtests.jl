using Backtest
using Test

@testset "Backtest.jl" begin
    # Write your tests here.
end

module T
  using ..ID: AssetId, FieldId
  using ..Engine: CalcLattice, newbar!, addfield!, addfields!
  using ..AbstractFields: AbstractFieldOperation
  using ..ConcreteFields: Open, Close, SMA, ZScore

  # using ..BT.DataReader: InMemoryDataReader

  function idtest()
  end

  function abstractfieldstest()
  end

  function concretefieldstest()
  end

  function datareadertest()
    btcbasepath = "../../data/crypto/individual_csvs/"
    daysofmonth = ("01", "02", "03", "04")
    btcpaths = [string("2019-06-", dayofmonth, ".csv") for dayofmonth in daysofmonth]
    singlefile = InMemoryDataReader(btcpaths[1])

  end

  function backtesttest()

  end

end

end;

# Backtest.Test.enginetest()
function inmemorydatareadertest()

end
# Backtest.Test.backtesttest()
