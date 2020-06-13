module AbstractFields

include("new_id.jl")
using .ID: AssetId, FieldId

export AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation

"""
`AbstractFieldOperation` is the mother of all field operations.
Required subtypes:
1. name: fieldid; type: FieldId; description: the name of the field!
"""
abstract type AbstractFieldOperation end

"""
`AbstractGenesisFieldOperation` is the type of a field operation
that relies on no other data. This can be thought of as an identity
operation, since there is actually no operation applied to the data
in this field. This FieldOperation is used for data that is generated
from outside of the backtest, such as market data.

Required subtypes:
1. All subtypes for `AbstractFieldOperation`.
"""
abstract type AbstractGenesisFieldOperation end

"""
`AbstractDownstreamFieldOperation` is the type shared by all field operations
that depend on upstream data before being calculated. An example of this would
be any window or cross sectional field operation, since they depend on some other
source of data to exist before they can be calculated. 

Required subtypes:
1. All subtypes needed for `AbstractFieldOperation`.
2. name: `upstreamfieldid`; type: FieldId; description: field id associated with the upstream dependency
"""
abstract type AbstractDownstreamFieldOperation <: AbstractFieldOperation end

"""
`AbstractWindowFieldOperation` is the mother of all concrete WindowFieldOperation
types. All child types are expected to have an integer `window` subtype.

Required subtypes:
1. All subtypes required by `AbstractDownstreamFieldOperation`.
2. name: `window`; type: Integer; description: number of bars of data over which to make the calculation.
"""
abstract type AbstractWindowFieldOperation <: AbstractDownstreamFieldOperation end

function dofieldop(windowfieldoperation::AbstractWindowFieldOperation, data::Vector)
    throw("Cannot perform field operation on `AbstractWindowFieldOperation`. Only concrete child types can be consumed by `dofieldop`.")
end

"""
`AbstractCrossSectionalFieldOperation` is the mother of all concrete 
CrossSectionalFieldOperation types.

Required subtypes:
1. All subtypes needed for `AbstractDownstreamFieldOperation`.
"""
abstract type AbstractCrossSectionalFieldOperation <: AbstractDownstreamFieldOperation end

function dofieldop(abstractcrosssectionalfieldoperation::AbstractCrossSectionalFieldOperation, data::Dict{AssetId, Any})::Dict{AssetId, Any}
    throw("Cannot perform field operation on `AbstractCrossSectionalFieldOperation`. Only concrete child types can be consumed by `dofieldop`.")
end

end