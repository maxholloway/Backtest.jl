module Engine

include("new_id.jl")
include("abstractfields.jl")

using Printf
using .ID: AssetId, FieldId
using .AbstractFields: AbstractFieldOperation


## BarLayer definition and related functions ##
struct BarLayer
    bardata::Dict{AssetId, Dict{FieldId, Any}} # map to a map to a value
end

function getvalue(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId)
    return barlayer[assetid][fieldid]
end

function hasvalue(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId)
    return haskey(barlayer.bardata, assetid) && haskey(barlayer.bardata[assetid], fieldid)
end

function insertvalue!(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId, value)
    if !haskey(barlayer.bardata)
        barlayer.bardata[assetid] = Dict{FieldId, Any}()
    end
    barlayer.bardata[assetid][fieldid] = value
end

function getallvalues(barlayer::BarLayer)
    return barlayer.bardata
end

## Counter definition (util) and related functions ##
struct Counter{T}
    data::Dict{T, Integer}
    Counter{T}() where T <: Any = new{T}(Dict{T, Integer}())
end
Counter() = Counter{Any}()

function hitcounter!(counter::Counter, key)
    # NOTE: Consider placing a lock here to make counter thread-safe
    if !haskey(counter, key)
        counter.data[key] = 0
    end
    counter.data[key] += 1;
end

function getcount(counter::Counter, key)
    # NOTE: Consider placing a lock here to make counter thread-safe
    return counter.data[key]
end

## CalcLattice definition and related methods ##
export CalcLattice
mutable struct CalcLattice
    # Attributes that remain constant
    assetids::Set{AssetId}
    fieldids::Vector{FieldId} # TODO: consider making a CalcLatticeFieldInfo struct that's created before CalcLattice
    numbarsstored::Integer
    
    # Attributes maintaining storage and access of bars
    recentbars::Array{BarLayer, 1} # most recent -> least recent
    curbarindex::Integer

    # Attributes that change when new bar propagation occurs
    numcompletedassets::Counter{FieldId}

    # Attributes changed when fields are added
    windowdependentfields::Dict{FieldId, Set{FieldId}}
    crosssectionaldependentfields::Dict{FieldId, Set{FieldId}}
    fieldids_to_ops::Dict{FieldId, AbstractFieldOperation}
    genesisfieldids::Set{FieldId}
end

function CalcLattice(nbarsstored::Integer, assetids::Set{AssetId})::CalcLattice
    return CalcLattice(
        assetids,                       # asset ids
        Vector{FieldId}(),              # field ids
        nbarsstored,                    # num bars stored
        Array{BarLayer, 1}(undef, nbarsstored), # recent bars
        0,                              # initialize curbarindex (one too small, since incrementing occurs on newbar addition)
        Counter{FieldId}(),             # number of completed assets for each field on this bar
        Dict{FieldId, Set{FieldId}}(),  # window dependent fields
        Dict{FieldId, Set{FieldId}}(),  # cross sectional dependent fields
        Dict{FieldId, AbstractFieldOperation}(),       # field ids to field ops
        Set()                           # genesis field ids
    )
end

function getnbaragodata(lattice::CalcLattice, ago::Integer)::BarLayer
    if ago > lattice.curbarindex
        throw("Invalid `ago` > $(@sprintf("%i", lattice.curbarindex))")
    end
    return lattice.recentbars[ago+1]
end

function getcurrentbar(lattice::CalcLattice)::BarLayer
    return getnbaragodata(lattice, 0)
end

function updatebars!(lattice::CalcLattice)::Nothing
    if lattice.curbarindex > lattice.numbarsstored
        pop!(lattice.recentbars) # remove the least recent bar
        pushfirst!(lattice.recentbars, Dict()) # push a more recent bar
    end
end

function insertnode!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId, value)::Nothing
    currentbar = getcurrentbar(lattice)
    if hasvalue(currentbar, assetid, fieldid) # check if node exists already
        throw("Attempted to insert a node that was already inserted!")
    else
        hitcounter!(lattice.numcompletedassets, fieldid)
        insertvalue!(currentbar, assetid, fieldid, value)
    end
end

function compute!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)::Nothing
    """Computes a window operation node.
    """
    # Get data for the window operation (time is the free variable)
    windowfieldoperation = lattice.fieldids_to_ops[fieldid]
    upstreamfieldid = getupstreamfieldid(windowfieldoperation)  
    window = windowfieldoperation.window
    windowdata = Vector(undef, window)
    for i in 1:window
        windowdata[i] = getvalue(lattice.recentbars[i], assetid, upstreamfieldid)
    end

    # Perform the window operation
    value = dofieldop(windowfieldoperation, windowdata)

    # Set value for this node
    insertnode!(lattice, assetid, fieldid)
end

function compute!(lattice::CalcLattice, fieldid::FieldId)::Nothing
    """Computes the node for all of the assetes of a cross sectional field.
    """
    # Get data for the cross sectional operation (asset is the free variable)
    crosssectionalfieldoperation = lattice.fieldids_to_ops[fieldid]
    upstreamfieldid = getupstreamfieldid(crosssectionalfieldoperation)
    currentbar = getcurrentbar(lattice)
    assetdata = Dict{AssetId, Any}()
    for assetid in lattice.assetids
        assetdata[assetid] = getvalue(currentbar, assetid, upstreamfieldid)
    end

    # Perform the cross sectional operation
    asset_results::Dict{AssetId, Any} = dofieldop(crosssectionalfieldoperation, assetdata)

    # Set value for all assets on this bar and field
    for assetid in lattice.assetids
        insertnode!(lattice, assetid, fieldid)
    end
end

function propagate!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)::Nothing
    """Given that this node has a value already, propagate forward
    through its dependent nodes.
    """

    # Propagate over all window fields that depend on this field
    if fieldid in lattice.windowdependentfields
        for windowdependentfieldid in lattice.windowdependentfields[fieldid]
            compute!(lattice, assetid, windowdependentfieldid)
            propagate!(lattice, assetid, windowdependentfieldid)
        end
    end

    # Propagate over all cross sectional fields that depend on this field
    hascrosssectionaldependencies = haskey(lattice.crosssectionaldependentfields, fieldid)
    allassetscompleted = (getcount(lattice.numcompletedassets, fieldid) == length(lattice.assetids))
    if hascrosssectionaldependencies && allassetscompleted
        for crosssectionaldependentfieldid in lattice.crosssectionaldependentfields[fieldid]
            compute!(lattice, fieldid)
            for assetid_ in lattice.assetids
                propagate!(lattice, assetid_, crosssectionaldependentfieldid)
            end
        end
    end

end

# Interface functions
export newbar!, addfield!
function newbar!(lattice::CalcLattice, newbardata::Dict{AssetId, Dict{FieldId, Any}})::Nothing
    
    lattice.numcompletedassets = Counter()
    lattice.curbarindex += 1
    updatebars!(lattice)

    # Populate lattice with genesis new bar data
    for assetid in keys(newbardata)
        for fieldid in lattice.genesisfieldids
            value = newbardata[assetid][fieldid]
            insertnode!(lattice, assetid, fieldid, value)
            propagate!(lattice, assetid, fieldid)
        end
    end
end

function addfield!(lattice::CalcLattice, newfieldoperation::AbstractFieldOperation)::Nothing
    if lattice.curbarindex != 0
        throw("Cannot add a field after bar data has been added.")
    end

    if newfieldoperation.fieldid in lattice.fieldids
        throw("Cannot have two fields with the same `fieldid`!")
    end

    push!(lattice.fieldids, newfieldoperation.fieldid)

    # Add the upstreamfieldid -> fieldid relationship
    if isa(newfieldoperation, AbstractGenesisFieldOperation)
        push!(lattice.genesisfieldids, newfieldoperation.fieldid)
    elseif isa(newfieldoperation, AbstractWindowFieldOperation)
        push!(lattice.windowdependentfields[newfieldoperation.upstreamfieldid], newfieldoperation.fieldid)
    elseif isa(newfieldoperation, AbstractCrossSectionalFieldOperation)
        push!(lattice.crosssectionaldependentfields[newfieldoperation.upstreamfieldid], newfieldoperation.fieldid)
    else
        throw("Currently, the only supported field operations are subtypes of `AbstractGenesisFieldOperation`, `AbstractWindowFieldOperation`, or `AbstractCrossSectionalFieldOperation`.")
    end

    lattice.fieldids_to_ops[newfieldoperation.fieldid] = newfieldoperation
end

end;