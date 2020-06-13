module ConcreteFields

include("abstractfields.jl")
include("new_id.jl")
using .ID: FieldId
using .AbstractFields: AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation

## Common genesis field operations ##
struct Open <: AbstractGenesisFieldOperation
    fieldid::FieldId
    Open()=new(FieldId("Open"))
    Open(fieldid::FieldId) = new(fieldid)
end

struct High <: AbstractGenesisFieldOperation
    fieldid::FieldId
    High()=new(FieldId("High"))
end

struct Low <: AbstractGenesisFieldOperation
    fieldid::FieldId
    Low()=new(FieldId("Low"))
end

struct Close <: AbstractGenesisFieldOperation
    fieldid::FieldId
    Close()=new(FieldId("Close"))
end

struct Volume <: AbstractGenesisFieldOperation
    fieldid::FieldId
    Volume()=new(FieldId("Volume"))
end

## Common window field operations ##
struct SMA <: AbstractWindowFieldOperation
    fieldid::FieldId
    upstreamfieldid::FieldId
    window::Integer
end

function dofieldop(windowfieldoperation::SMA, data::Vector{Number})
    return sum(data)/length(data)
end


## Common cross sectional field operations ##

end