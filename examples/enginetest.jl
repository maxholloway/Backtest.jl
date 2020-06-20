include("new_engine.jl")
using .ID: AssetId, FieldId
using .Engine: CalcLattice, newbar!, addfield!
using .AbstractFields: AbstractFieldOperation
using .ConcreteFields: Open, SMA

function main()
    openid = FieldId("Open")
    smaid = FieldId("SMA-Open-15")
    smawindow = 15
    fields = Array{T}([
        Open(openid),
        SMA(smaid, openid, smawindow)
    ]) where T <: AbstractFieldOperation
    println(fields)
end

main() # run the main function

