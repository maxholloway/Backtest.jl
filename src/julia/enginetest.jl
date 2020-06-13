include("new_id.jl")
using .ID: AssetId, FieldId

include("new_engine.jl")
using .Engine: CalcLattice, newbar!, addfield!

include("concretefields.jl")
using .ConcreteFields: Open, SMA

function main()
    openid = FieldId("Open")
    smaid = FieldId("SMA-Open-15")
    smawindow = 15
    fields = [
        Open(openid),
        SMA(smaid, openid, smawindow)
    ]
end

main() # run the main function