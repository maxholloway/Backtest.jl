module Backtest

module ID

  ## Basic type definitions ##
  abstract type Id end

  struct AssetId <: Id
    assetid::String
  end

  struct FieldId <: Id
    fieldid::String
  end

end

module AbstractFields

  using ..ID: AssetId, FieldId

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
  abstract type AbstractGenesisFieldOperation <: AbstractFieldOperation end

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

  export AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation

end

module ConcreteFields

  using ..ID: FieldId
  using ..AbstractFields: AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation

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
    Close(fieldid::FieldId) = new(fieldid)
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

  function dofieldop(windowfieldoperation::SMA, data::Vector{T}) where {T<:Number}
    return sum(data)/length(data)
  end


  ## Common cross sectional field operations ##

end

module Engine
  using Printf
  using ..ID: AssetId, FieldId
  using ..AbstractFields: AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
  using ..ConcreteFields: dofieldop

  ## BarLayer definition and related functions ##
  struct BarLayer
    bardata::Dict{AssetId, Dict{FieldId, T}} where {T<:Any} # map to a map to a value
  end

  function getvalue(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId)
    return barlayer.bardata[assetid][fieldid]
  end

  function hasvalue(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId)
    return haskey(barlayer.bardata, assetid) && haskey(barlayer.bardata[assetid], fieldid)
  end

  function insertvalue!(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId, value)
    if !haskey(barlayer.bardata, assetid)
      barlayer.bardata[assetid] = Dict{FieldId, typeof(value)}()
    end
    barlayer.bardata[assetid][fieldid] = value
  end

  function getallvalues(barlayer::BarLayer)
    return barlayer.bardata
  end

  ## Counter definition (util) and related functions ##
  struct Counter{T}
    data::Dict{T, Integer}
    Counter{T}() where {T <: Any} = new{T}(Dict{T, Integer}())
  end

  function hitcounter!(counter::Counter, key)
    # NOTE: Consider placing a lock here to make counter thread-safe
    if !haskey(counter.data, key)
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
      assetids,             # asset ids
      Vector{FieldId}(),        # field ids
      nbarsstored,          # num bars stored
      Array{BarLayer, 1}(undef, 0), # recent bars
      0,                # initialize curbarindex (one too small, since incrementing occurs on newbar addition)
      Counter{FieldId}(),       # number of completed assets for each field on this bar
      Dict{FieldId, Set{FieldId}}(),  # window dependent fields
      Dict{FieldId, Set{FieldId}}(),  # cross sectional dependent fields
      Dict{FieldId, AbstractFieldOperation}(),     # field ids to field ops
      Set()               # genesis field ids
    )
  end

  function getnbaragodata(lattice::CalcLattice, ago::Integer)::BarLayer
    if (ago > length(lattice.recentbars)) || (ago > lattice.numbarsstored) || (ago < 0)
      throw("Invalid `ago` $(@sprintf("%i", lattice.curbarindex)).")
    end
    mostrecentbarindex = length(lattice.recentbars)
    return lattice.recentbars[mostrecentbarindex-ago]
  end

  function getcurrentbar(lattice::CalcLattice)::BarLayer
    return getnbaragodata(lattice, 0)
  end

  function updatebars!(lattice::CalcLattice)
    if length(lattice.recentbars) >= lattice.numbarsstored
      deleteat!(lattice.recentbars, 1) # delete least recent bar
    end

    barlayer = BarLayer(Dict{AssetId, Dict{FieldId, Any}}())
    push!(lattice.recentbars, barlayer)
  end

  function insertnode!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId, value)
    # print("Asset id: "); println(assetid)
    # print("Field id: "); println(fieldid)
    # print("Value: "); println(value)
    currentbar = getcurrentbar(lattice)
    # println("Got current bar.")
    if hasvalue(currentbar, assetid, fieldid) # check if node exists already
      throw("Attempted to insert a node that was already inserted!")
    else
      hitcounter!(lattice.numcompletedassets, fieldid)
      insertvalue!(currentbar, assetid, fieldid, value)
    end
  end

  function getwindowdata(lattice::CalcLattice, windowfieldoperation::AbstractWindowFieldOperation, assetid::AssetId)::Vector
    # Get information about the operation
    upstreamfieldid = windowfieldoperation.upstreamfieldid
    window = windowfieldoperation.window
    inputdatatype = typeof( getvalue(lattice.recentbars[1], assetid, upstreamfieldid) )

    # Set looping parameters
    numdefinedentries = length(lattice.recentbars)
    lower = max(1, numdefinedentries-window+1)
    upper = numdefinedentries
    
    # Fill window data
    windowdata = Vector{inputdatatype}(undef, upper-lower+1)
    for i in lower:upper
      value = getvalue(lattice.recentbars[i], assetid, upstreamfieldid)
      windowdata[i-lower+1] = value
    end
    return windowdata
  end
  
  function compute!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)
    """Computes a window operation node.
    """
    windowfieldoperation = lattice.fieldids_to_ops[fieldid]
    # Get data for the window operation (time is the free variable)
    windowdata = getwindowdata(lattice, windowfieldoperation, assetid)

    # Perform the window operation
    value = dofieldop(windowfieldoperation, windowdata)
    # println("Finished `dofieldop`!")
    # Set value for this node
    insertnode!(lattice, assetid, fieldid, value)
  end

  function compute!(lattice::CalcLattice, fieldid::FieldId)
    """Computes the node for all of the assetes of a cross sectional field.
    """
    # Get data for the cross sectional operation (asset is the free variable)
    crosssectionalfieldoperation = lattice.fieldids_to_ops[fieldid]
    upstreamfieldid = crosssectionalfieldoperation.upstreamfieldid
    currentbar = getcurrentbar(lattice)
    assetdata = Dict{AssetId, Any}()
    for assetid in lattice.assetids
      assetdata[assetid] = getvalue(currentbar, assetid, upstreamfieldid)
    end

    # Perform the cross sectional operation
    asset_results::Dict{AssetId, Any} = dofieldop(crosssectionalfieldoperation, assetdata)

    # Set value for all assets on this bar and field
    for assetid in lattice.assetids
      insertnode!(lattice, assetid, fieldid, asset_results[assetid])
    end
  end

  function propagate!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)
    """Given that this node has a value already, propagate forward
    through its dependent nodes.
    """

    # Propagate over all window fields that depend on this field
    if haskey(lattice.windowdependentfields, fieldid)
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
  function newbar!(lattice::CalcLattice, newbardata::Dict{AssetId, Dict{FieldId, T}}) where {T}
    
    lattice.numcompletedassets = Counter{FieldId}()
    lattice.curbarindex += 1
    # print("New bar and `curbarindex` is "); println(lattice.curbarindex)
    updatebars!(lattice)
    # println("Here!\n\n\n")
    # print("Genesis field ids: ")
    # println(lattice.genesisfieldids)
    # Populate lattice with genesis new bar data
    for assetid in keys(newbardata)
      for fieldid in lattice.genesisfieldids
        value = newbardata[assetid][fieldid]
        # print("Vaue for "); print(assetid); print(", "); print(fieldid); print(": "), println(value)
        insertnode!(lattice, assetid, fieldid, value)
        propagate!(lattice, assetid, fieldid)
      end
    end
  end

  function addfield!(lattice::CalcLattice, newfieldoperation::AbstractFieldOperation)
    if lattice.curbarindex != 0
      throw("Cannot add a field after bar data has been added.")
    end

    if newfieldoperation.fieldid in lattice.fieldids
      throw("Cannot have two fields with the same `fieldid`!")
    end

    function appendtodict!(dict::Dict{FieldId, Set{FieldId}}, key::FieldId, value::FieldId)
      if !(key in keys(dict))
        dict[key] = Set()
      end
      push!(dict[key], value)
    end
    
    push!(lattice.fieldids, newfieldoperation.fieldid)

    # Add the upstreamfieldid -> fieldid relationship
    if isa(newfieldoperation, AbstractGenesisFieldOperation)
      push!(lattice.genesisfieldids, newfieldoperation.fieldid)
    elseif isa(newfieldoperation, AbstractWindowFieldOperation)
      appendtodict!(lattice.windowdependentfields, newfieldoperation.upstreamfieldid, newfieldoperation.fieldid)
    elseif isa(newfieldoperation, AbstractCrossSectionalFieldOperation)
      appendtodict!(lattice.crosssectionaldependentfields, newfieldoperation.upstreamfieldid, newfieldoperation.fieldid)
    else
      throw("Currently, the only supported field operations are subtypes of `AbstractGenesisFieldOperation`, `AbstractWindowFieldOperation`, or `AbstractCrossSectionalFieldOperation`.")
    end
    # println("\n\nHERE\n\n\n")
    lattice.fieldids_to_ops[newfieldoperation.fieldid] = newfieldoperation
    # println("\n\nHERE\n\n\n")
  end

end

module Test
  using Random
  using ..ID: AssetId, FieldId
  using ..Engine: CalcLattice, newbar!, addfield!
  using ..AbstractFields: AbstractFieldOperation
  using ..ConcreteFields: Open, Close, SMA
  function idtest()

  end

  function abstractfieldstest()

  end

  function concretefieldstest()

  end
  
  function enginetest()

    # Make a backtest object
    nbarstostore = 100000
    assetids = Set([AssetId("AAPL"), AssetId("MSFT"), AssetId("TSLA")])
    lattice = CalcLattice(nbarstostore, assetids)


    function rand_(base::Number)
      SEED = 1234
      rng = MersenneTwister(SEED)
      result = base*(1+randn(rng))
      return base
    end
    
    # Make data
    allbars = [
      Dict(
        AssetId("AAPL") => Dict(FieldId("Open") => rand_(10*i), FieldId("Close") => rand_(12*i)),
        AssetId("MSFT") => Dict(FieldId("Open") => rand_(20*i), FieldId("Close") => rand_(25*i)),
        AssetId("TSLA") => Dict(FieldId("Open") => rand_(30*i), FieldId("Close") => rand_(25*i))
      ) for i in 1:nbarstostore
    ]
    # println(allbars)
    # println()
    # println(allbars[6][AssetId("TSLA")][FieldId("Open")])

    # Make fields
    fields = Vector([
      Open(FieldId("Open")),
      Close(FieldId("Close")),
      SMA(FieldId("SMA-Open-1"), FieldId("Open"), 1),
      SMA(FieldId("SMA-Open-2"), FieldId("Open"), 2),
      SMA(FieldId("SMA-Close-3"), FieldId("Close"), 3)
    ])
    # print("Fields: ")
    # println(fields)
    
    for field in fields
      addfield!(lattice, field)
    end

    # print("Dict afterward: ")
    # println(lattice.windowdependentfields)
    

    # Feed bars into engine
    @time begin
    for bar in allbars
      newbar!(lattice, bar)
    end
    end
    
    # println(lattice.recentbars[lattice.numbarsstored])

  end

end

end;

Backtest.Test.enginetest()