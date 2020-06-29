module Backtest
  module Ids
    const AssetId = String
    const FieldId = String
    const OrderId = String
  end # module

  module Exceptions
    using Dates
    using ..Ids: AssetId

    struct AbstractMethodError <: Exception
      msg::String
      AbstractMethodError(cls::Type, method::Function) = new(
        string("Cannot run  method ", method, " with abstract class ", cls, ".")
      )
    end


    struct DateTooEarlyError <: Exception
      msg::String
      function DateTooEarlyError(requestedtime::T, assetid::AssetId ) where {T<:Dates.TimeType}
        return new( string("The requested time, ", requestedtime, ", is before the first time", " in ", assetid, "."))
      end
    end

    struct DateTooFarOutError <: Exception
      msg::String
      DateTooFarOutError(requestedtime::T, assetid::AssetId) where {T<:Dates.TimeType} = new(
        string("There is not enough data in ", assetid, " to access ", requestedtime, ".")
      )
    end

    function _test()
      try
        # throw(AbstractMethodError(AbstractString, print))
        throw(DateTooFarOutError(Dates.DateTime(2020), "~~datareader~~"))
      catch e
        if isa(e, DateTooFarOutError)
          println("It's ok!")
        else
          println(println(typeof(e)))
        end
      end
    end
  end # module

  module AbstractFields
    using ..Ids: AssetId, FieldId

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
      throw(Exceptions.AbstractMethodError(AbstractWindowFieldOperation, dofieldop))
    end

    """
      `AbstractCrossSectionalFieldOperation` is the mother of all concrete
      CrossSectionalFieldOperation types.

      Required subtypes:
      1. All subtypes needed for `AbstractDownstreamFieldOperation`.
    """
    abstract type AbstractCrossSectionalFieldOperation <: AbstractDownstreamFieldOperation end

    function dofieldop(abstractcrosssectionalfieldoperation::AbstractCrossSectionalFieldOperation, data::Dict{AssetId, Any})::Dict{AssetId, Any}
      throw(AbstractWindowFieldOperation(AbstractCrossSectionalFieldOperation, dofieldop))
    end

    export AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
  end # module

  module ConcreteFields
    using ..Ids: AssetId, FieldId
    using ..AbstractFields: AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
    using Statistics
    using NamedArrays


    ## Common genesis field operations ##
    struct Open <: AbstractGenesisFieldOperation
      fieldid::FieldId
      Open()=new(FieldId("Open"))
      Open(fieldid::FieldId) = new(fieldid)
    end

    struct High <: AbstractGenesisFieldOperation
      fieldid::FieldId
      High()=new(FieldId("High"))
      High(fieldid::FieldId) = new(fieldid)
    end

    struct Low <: AbstractGenesisFieldOperation
      fieldid::FieldId
      Low()=new(FieldId("Low"))
      Low(fieldid::FieldId) = new(fieldid)
    end

    struct Close <: AbstractGenesisFieldOperation
      fieldid::FieldId
      Close()=new(FieldId("Close"))
      Close(fieldid::FieldId) = new(fieldid)
    end

    struct Volume <: AbstractGenesisFieldOperation
      fieldid::FieldId
      Volume()=new(FieldId("Volume"))
      Volume(fieldid::FieldId) = new(fieldid)
    end

    ## Common window field operations ##
    struct Returns <: AbstractWindowFieldOperation
      fieldid::FieldId
      upstreamfieldid::FieldId
      window::Integer
    end
    Returns(fieldid::FieldId, upstreamfieldid::FieldId) = Returns(fieldid, upstreamfieldid, 2)
    function dofieldop(returnsfieldop::Returns, data::Vector{T}) where {T<:Number}
      if length(data) < returnsfieldop.window
        return missing
      else
        return (data[returnsfieldop.window]-data[1])/data[1]
      end
    end


    struct LogReturns <: AbstractWindowFieldOperation
      fieldid::FieldId
      upstreamfieldid::FieldId
      window::Integer
    end
    LogReturns(fieldid::FieldId, upstreamfieldid::FieldId) = LogReturns(fieldid, upstreamfieldid, 2)
    function dofieldop(logreturnsfieldop::LogReturns, data::Vector{T}) where {T<:Number}
      if length(data) < logreturnsfieldop.window
        return missing
      else
        return log(data[logreturnsfieldop.window]/data[1])
      end
    end

    struct SMA <: AbstractWindowFieldOperation
      fieldid::FieldId
      upstreamfieldid::FieldId
      window::Integer
    end
    function dofieldop(windowfieldoperation::SMA, data::Vector{T}) where {T<:Number}
      return sum(data)/length(data)
    end


    ## Common cross sectional field operations ##
    struct ZScore <: AbstractCrossSectionalFieldOperation
      fieldid::FieldId
      upstreamfieldid::FieldId
    end
    function dofieldop(crosssectionalfieldoperation::ZScore, assetdata::NamedArray)::NamedArray
      mu = mean(assetdata)
      sigma = std(assetdata)
      for i in 1:length(assetdata)
        assetdata[i] = (assetdata[i]-mu)/sigma
      end
      return assetdata
    end


    struct Rank <: AbstractCrossSectionalFieldOperation
      fieldid::FieldId
      upstreamfieldid::FieldId
    end
    function dofieldop(crosssectionalfieldoperation::Rank, assetdata::NamedArray)::NamedArray
      result = NamedArray(Vector{Union{Integer, Nothing}}(nothing, length(assetdata)), names(assetdata, 1))
      sort!(assetdata, rev=true)
      for (i, assetid) in enumerate(names(assetdata, 1))
        result[assetid] = i
      end
      return result
    end
  end # module

  module DataReaders
    using Dates
    using CSV: read
    using DataFrames: DataFrame, nrow
    using ..Exceptions
    using ..Ids: AssetId, FieldId

    abstract type AbstractDataReader end
    function fastforward!(datareader::AbstractDataReader, time::T) where {T<:Dates.TimeType}
      """Function that moves datareader forward until the current
      bar is at or after `time`. This is part of the AbstractDataReader
      interface."""
      throw(Exceptions.AbstractMethodError(AbstractDataReader, fastforward!))
    end

    mutable struct InMemoryDataReader <: AbstractDataReader
      """Stores all asset data in memory."""
      assetid::AssetId
      data::DataFrame
    end
    function InMemoryDataReader(assetid::String, sources::Vector{S};
                                datetimecol::String="datetime",
                                dtfmt::String="yyyy-mm-dd HH:MM:SS",
                                delim::Char=',') where {S<:AbstractString}
      """Multi-datasource constructor."""
      if length(sources) == 0
        throw("`sources` must have at least one element.")
      end

      # Read first source, then append all others to the first.
      alldata = read(sources[1], delim=delim, copycols=true)
      for i = 2:length(sources)
        otherdf = append!(alldata, DataFrame(read(sources[i], delim=delim), copycols=true))
      end

      # Convert the datetime column
      alldata[!, datetimecol] = Dates.DateTime.(alldata[:, datetimecol], Dates.DateFormat(dtfmt))
      return InMemoryDataReader(assetid, alldata)
    end
    InMemoryDataReader(assetid::String, source::String; datetimecol::String="datetime",
        dtfmt::String="yyyy-mm-dd HH:MM:SS", delim::Char=',') =
      InMemoryDataReader(assetid, [source], datetimecol=datetimecol, dtfmt=dtfmt, delim=delim)

    function fastforward!(datareader::InMemoryDataReader, time::T) where {T<:Dates.TimeType}
      if nrow(datareader.data) == 0
        throw("`DataReader` has no data.")
      elseif datareader.data[1, 1] > time
        throw(Exceptions.DateTooEarlyError(time, datareader.assetid))
      end
      while nrow(datareader.data) > 0 && datareader.data[1, 1] < time # NOTE: ASSUMES DATETIME IS THE FIRST COLUMN
        datareader.data = datareader.data[2:nrow(datareader.data), :]
      end

      if nrow(datareader.data) == 0
        throw(Exceptions.DateTooFarOutError(time, datareader.assetid))
      end
    end

    function peek(datareader::InMemoryDataReader)::Dict{FieldId, Any}
      toprow::NamedTuple = copy(datareader.data[1, :])
      fieldtovalues::Dict{FieldId, Any} = Dict{FieldId, Any}()
      for kvpair in zip(fieldnames(typeof(toprow)), toprow)
        fieldtovalues[string(kvpair[1])] = kvpair[2]
      end
      return fieldtovalues
    end

    function popfirst!(datareader::InMemoryDataReader)::Dict{FieldId, Any}
      fieldtovalues = peek(datareader)
      delete!(datareader.data, 1)
      return fieldtovalues
    end
  end # module

  module Engine
    using NamedArrays: NamedArray
    using ..Ids: AssetId, FieldId
    using ..AbstractFields: AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
    using ..ConcreteFields: dofieldop
    ## BarLayer definition and related functions ##
    struct BarLayer
      bardata::NamedArray{T, 2} where {T<:Any}
    end

    function BarLayer(assetids::Vector{AssetId}, fieldids::Vector{FieldId})
      unnamedarray = Array{Any, 2}(undef, length(assetids), length(fieldids))
      return BarLayer(NamedArray(unnamedarray, (assetids, fieldids)))
    end

    function getvalue(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId)
      return barlayer.bardata[assetid, fieldid]
    end

    function insertvalue!(barlayer::BarLayer, assetid::AssetId, fieldid::FieldId, value)
      barlayer.bardata[assetid, fieldid] = value
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
      assetids::Vector{AssetId}
      fieldids::Vector{FieldId} # TODO: consider making a CalcLatticeFieldInfo struct that's created before CalcLattice
      numbarsstored::Integer

      # Attributes maintaining storage and access of bars
      recentbars::Vector{BarLayer} # most recent -> least recent
      curbarindex::Integer

      # Attributes that change when new bar propagation occurs
      numcompletedassets::Counter{FieldId}

      # Attributes changed when fields are added
      windowdependentfields::Dict{FieldId, Set{FieldId}}
      crosssectionaldependentfields::Dict{FieldId, Set{FieldId}}
      fieldids_to_ops::Dict{FieldId, AbstractFieldOperation}
      genesisfieldids::Set{FieldId}
    end

    function CalcLattice(nbarsstored::Integer, assetids::Vector{AssetId})::CalcLattice
      return CalcLattice(
        assetids,             # asset ids
        Vector{FieldId}(),        # field ids
        nbarsstored,          # num bars stored; if -1, then store all bars
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
      if (ago > length(lattice.recentbars)) || (ago < 0) || ((lattice.numbarsstored!=-1) && (ago > lattice.numbarsstored))
        throw(string("Invalid `ago`: ", ago, " while lattice is only on the ", lattice.curbarindex, " index."))
      end
      mostrecentbarindex = length(lattice.recentbars)
      return lattice.recentbars[mostrecentbarindex-ago]
    end

    function getcurrentbar(lattice::CalcLattice)::BarLayer
      return getnbaragodata(lattice, 0)
    end

    function updatebars!(lattice::CalcLattice)
      if (lattice.numbarsstored!=-1) && (length(lattice.recentbars) >= lattice.numbarsstored)
        deleteat!(lattice.recentbars, 1) # delete least recent bar
      end

      barlayer = BarLayer(lattice.assetids, lattice.fieldids)
      push!(lattice.recentbars, barlayer)
    end

    function insertnode!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId, value)
      currentbar = getcurrentbar(lattice)
      # TODO: Add functionality to check if this value already exists
      hitcounter!(lattice.numcompletedassets, fieldid)
      insertvalue!(currentbar, assetid, fieldid, value)
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

    function getcrosssectionaldata(lattice::CalcLattice, crosssectionalfieldoperation::AbstractCrossSectionalFieldOperation)::NamedArray
      upstreamfieldid = crosssectionalfieldoperation.upstreamfieldid
      currentbar = getcurrentbar(lattice)
      emptyassets = Vector(undef, length(lattice.assetids))
      assetdata = NamedArray(emptyassets, lattice.assetids)
      for assetid in lattice.assetids
        assetdata[assetid] = getvalue(currentbar, assetid, upstreamfieldid)
      end
      return assetdata
    end

    function compute!(lattice::CalcLattice, fieldid::FieldId)
      """Computes the node for all of the assetes of a cross sectional field.
      """
      crosssectionalfieldoperation = lattice.fieldids_to_ops[fieldid]
      # Get data for the cross sectional operation (asset is the free variable)
      assetdata = getcrosssectionaldata(lattice, crosssectionalfieldoperation)

      # Perform the cross sectional operation
      asset_results::NamedArray = dofieldop(crosssectionalfieldoperation, assetdata)

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
          compute!(lattice, crosssectionaldependentfieldid)
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
      updatebars!(lattice)
      for assetid in keys(newbardata)
        for fieldid in lattice.genesisfieldids
          value = newbardata[assetid][fieldid]
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
      lattice.fieldids_to_ops[newfieldoperation.fieldid] = newfieldoperation
    end

    function addfields!(lattice::CalcLattice, newfieldoperations::Vector{<:AbstractFieldOperation})
      for newfieldoperation in newfieldoperations
        addfield!(lattice, newfieldoperation)
      end
    end
  end # module

  module Orders
    using ..Ids: AssetId

    abstract type AbstractOrder end

    struct MarketOrder <: AbstractOrder
      assetid::AssetId
      size::NT where {NT<:Number}
    end

    struct LimitOrder <: AbstractOrder
      assetid::AssetId
      size::ST where {ST<:Number}
      extremum::ET where {ET<:Number}
    end
  end # module

  module Events
    using Dates: TimeType
    using ..Ids: AssetId, FieldId, OrderId
    using ..Orders: AbstractOrder

    # Event definitions #
    """ `AbstractEvent` is the ancestor to all concrete events.
    Required subtypes:
    1. name: time; type: datetime; description: the time at which the event should be fired (with respect to the time of the backtest, not the real datetime)
    """
    abstract type AbstractEvent end

    struct NewBarEvent <: AbstractEvent
      time::T where {T<:TimeType}
      genesisdata::Dict{AssetId, Dict{FieldId, A}} where {A<:Any}
    end

    struct FieldCompletedProcessingEvent <: AbstractEvent
      time::T where {T<:TimeType}
    end

    abstract type AbstractOrderEvent <: AbstractEvent end

    struct OrderAckEvent <: AbstractOrderEvent
      time::T where {T<:TimeType} # when the ack is received on our end
      orderid::String
    end

    struct OrderFillEvent <: AbstractOrderEvent
      time::T where {T<:TimeType} # when the ack is received on our end
      order::O where {O<:AbstractOrder}
      deltacash::Number # change in cash as a result of this order being filled
      deltaequity::Number # change in our equity in this asset
    end

    # Event queue type and related definitions #
    struct EventQueue
      events::Vector{T} where {T<:AbstractEvent} # all events, stored in chronological order (closest in the future -> furthest in the future)
      EventQueue() = new(Vector{AbstractEvent}(undef, 0))
    end

    function peek(eventq::EventQueue)
      return eventq.events[1]
    end

    function pop!(eventq::EventQueue)
      return popfirst!(eventq.events)
    end

    function push!(eventq::EventQueue, event::T) where {T<:AbstractEvent}
      index = searchsortedfirst(eventq.events, event, by=(event->event.time))
      insert!(eventq.events, index, event)
    end

    function empty(eventq::EventQueue)
      return length(eventq.events) == 0
    end
  end # module

  ## Imports
  using Dates: DateTime, TimeType, Minute, Millisecond
  using Dates
  using UUIDs: uuid4
  using NamedArrays: NamedArray
  using .Ids: AssetId, FieldId, OrderId
  using .AbstractFields: AbstractFieldOperation
  using .ConcreteFields: Open, High, Low, Close, Volume
  using .Events: EventQueue, AbstractEvent, NewBarEvent, FieldCompletedProcessingEvent, OrderFillEvent, AbstractOrderEvent, OrderAckEvent
  using .Events
  using .Orders
  using .Engine: CalcLattice, addfields!, newbar!
  using .DataReaders: AbstractDataReader, fastforward!, popfirst!, peek

  ## Verbosity Levels ##
  abstract type AbstractVerbosity end
  abstract type INFO <: AbstractVerbosity end
  abstract type TRANSACTIONS <: INFO end
  abstract type DEBUG <: TRANSACTIONS end
  abstract type WARNING <: DEBUG end
  abstract type NOVERBOSITY <: WARNING end

  ## Concrete types ##
  struct StrategyOptions
    datareaders::Dict{AssetId, DR} where {DR<:AbstractDataReader}
    fieldoperations::Vector{FO} where {FO<:AbstractFieldOperation}
    numlookbackbars::Integer
    start::ST where {ST<:Dates.TimeType}
    endtime::ET where {ET<:Dates.TimeType}
    tradinginterval::TTI where {TTI<:Dates.Period}
    verbosity::DataType
    datadelay::DDT where {DDT<:Dates.Period}
    messagelatency::ODT where {ODT<:Dates.Period}
    datetimecol::String
    opencol::String
    highcol::String
    lowcol::String
    closecol::String
    volumecol::String
    ondataevent!::TODE where {TODE<:Function}
    onorderevent!::TOE where {TOE<:Function}
    principal::PT where {PT<:Number}
  end
  function StrategyOptions(;
                          datareaders::Dict{AssetId, DR}, # data source for each asset
                          fieldoperations::Vector{FO},    # field operations to be performed
                          start::ST,                      # start time for the backtest (this is the DateTime of the first bar of data to be read; actions start one bar later)
                          endtime::ET,                    # end time for the backtest
                          numlookbackbars::Integer=-1,    # number of backtest bars to store; if -1, then all data is stored; if space is an issue, this can be changed to a positive #. However, this will limit how much data can be accessed.
                          tradinginterval::TTI=Minute(390), # how much time there is between the start of two consecutive bars
                          verbosity::Type=NOVERBOSITY,     # how much verbosity the backtest should have; INFO gives the most messages, and NOVERBOSITY gives the fewest
                          datadelay::DDT=Millisecond(100), # how much time transpires at the beginning of a bar before data is received; e.g. if this is 5 seconds, then data will be `received` by the backtest 5 seconds after the bar starts.
                          messagelatency::ODT=Millisecond(100), # how much time it takes to transmit a message to a brokerage/exchange
                          datetimecol::String="datetime", # name of datetime column
                          opencol::String="open",         # name of open column
                          highcol::String="high",         # name of high column
                          lowcol::String="low",           # name of low column
                          closecol::String="close",       # name of close column
                          volumecol::String="volume",     # name of volume column
                          ondataevent::Function=(dataevent->nothing), # user-defined function that performs logic when data is received
                          onorderevent::Function=(orderevent->nothing), # user-defined function that performs logic when an order event is received
                          principal::PT=100_000           # starting amount of buying power; in many cases this will be interpreted as a starting cash value
                          ) where { DR<:AbstractDataReader, FO<:AbstractFieldOperation,
                          ST<:Dates.TimeType, ET<:Dates.TimeType, TTI<:Dates.TimePeriod,
                          DDT<:Dates.Period, ODT<:Dates.Period, PT<:Number }
    return StrategyOptions(datareaders, fieldoperations, numlookbackbars,
      start, endtime, tradinginterval, verbosity, datadelay, messagelatency, datetimecol,
      opencol, highcol, lowcol, closecol, volumecol,  ondataevent, onorderevent,
      principal
    )
  end

  mutable struct Portfolio
    equity::Dict{AssetId, EN} where {EN<:Number} # amount of equity in each asset
    buyingpower::CN where {CN<:Number}
    value::VN where {VN<:Number} # total value of the portfolio
    Portfolio(buyingpower::N) where {N<:Number} = new(Dict{AssetId, Number}(), buyingpower, buyingpower)
  end

  mutable struct Strategy
    options::StrategyOptions
    events::EventQueue
    orders::Dict{OrderId, Orders.AbstractOrder}
    openorderids::Vector{OrderId}
    assetids::Vector{AssetId}
    portfolio::Portfolio
    lattice::CalcLattice
    curbarstarttime::DateTime
    curtime::DateTime
    curbarindex::Integer
  end
  function Strategy(options::StrategyOptions)
    """User-facing constructor."""
    # Prepare the data readers
    preparedatareaders!(options.datareaders, options.start)

    # Prepare the lattice
    assetids = [assetid for assetid in keys(options.datareaders)]
    lattice = CalcLattice(options.numlookbackbars, assetids)
    allfields = Vector{AbstractFieldOperation}(
      [
        Open(options.opencol), High(options.highcol), Low(options.lowcol),
        Close(options.closecol), Volume(options.volumecol)
      ]
    )
    append!(allfields, options.fieldoperations)
    addfields!(lattice, allfields)
    return Strategy(
      options,
      EventQueue(),
      Dict{OrderId, Orders.AbstractOrder}(),
      Vector{OrderId}(),
      assetids,
      Portfolio(options.principal),
      lattice,
      options.start,
      options.start,
      0
    )
  end

  ### Data Access Functions ###
  function getalldata(strat::Strategy)::Vector{NamedArray}
    """Returns a vector of (assetid, fieldid)-value pairs. The entries in the vector are in
    chronological order, meaning that the last entry will represent the most recent bar."""
    map((barlayer -> barlayer.bardata), strat.lattice.recentbars)
  end

  function data(strat::Strategy, ago::Integer)::NamedArray
    """Gets (assetid, fieldid)->value pairs for `ago` bars ago; if `ago=0`,
    this gets the previous bar's data."""
    alldata = getalldata(strat)
    return alldata[length(alldata)-ago]
  end

  function data(strat::Strategy, ago::Integer, fieldid::FieldId)::NamedArray
    """Gets (assetid)->value pairs for `ago` bars ago for a particular field;
    if ago=0, then this is equivalent to data(strat, fieldid)."""
    return data(strat, ago)[:, fieldid]
  end

  function data(strat::Strategy, ago::Integer, assetid::AssetId, fieldid::FieldId)
    """Gets the value for a particular field for a particular asset on a particular bar; if
    ago=0, then this is equivalent to data(strat, assetid, fieldid)."""
    return data(strat, ago)[assetid, fieldid]
  end

  function data(strat::Strategy)::NamedArray
    """Gets (assetid, fieldid)->value pairs for the previous bar.
    For example, if the time between bars is 1 minute, and the current time
    is 11:33:25 (HH:MM:SS), then this would give OHLCV data from
    11:32:00-11:32:59.999... . WE CANNOT ACCESS DATA FOR THE CURRENT BAR,
    SINCE IT IS NOT COMPLETED YET (e.g. cannot access this bar's open price)."""
    return data(strat, 0)
  end

  function data(strat::Strategy, fieldid::FieldId)::NamedArray
    """Gets assetid->value pairs for the previous bar."""
    return data(strat, 0, fieldid)
  end

  function data(strat::Strategy, assetid::AssetId, fieldid::FieldId)
    """Gets value for a particular field for a particular asset on the previous bar."""
    return data(strat, 0, assetid, fieldid)
  end

  function numbarsavailable(strat::Strategy)
    return strat.lattice.recentbars |> length
  end


  ## Utility functions ##
  function log(strat::Strategy, message::String, verbosity::Type)
    if verbosity <: strat.options.verbosity
      time = Dates.format(strat.curtime, "yyyy-mm-dd HH:MM:SS.sss")
      println(string(time, " ~~~~ ", message))
    end
  end

  function preparedatareaders!(datareaders::Dict{AssetId, DR}, time::DateTime) where {DR<:AbstractDataReader}
    """Fast forward each data reader, so that they're all able to read bars from
    the same starting point."""
    if length(keys(datareaders)) == 0
      throw(string("No datareaders specified. At least one datareader must be",
      " specified in order to run a backtest."))
    end

    for assetid in keys(datareaders)
      fastforward!(datareaders[assetid], time)
    end
  end


  curbarendtime(strat::Strategy) = strat.curbarstarttime + strat.options.tradinginterval

  function randomtimeininterval(left::LT, right::RT) where {LT<:Dates.TimeType, RT<:Dates.TimeType}
    leftms = Dates.datetime2epochms(left)
    rightms = Dates.datetime2epochms(right)
    randms = rand(leftms:rightms)
    return Dates.epochms2datetime(randms)
  end

  ## Methods related to orders ##
  function order!(strat::Strategy, order::OT)::OrderId where {OT<:Orders.AbstractOrder}
    """Place an order, and return the order id!
    Under the hood, there's a lot of machinery happening here. In our current workflow,
    we only check to fill orders once per bar. This is a limitation of our backtest's
    interface, and surely one would have a streaming API to receive notifications from their
    brokerage in real life. However, since our backtest is fundamentally synchronous, we
    must check __in this method__ to see if our order would fill during this particular
    bar. If not, then we push it onto a queue of open orders."""
    # Generate an order id; include loop for robustness
    orderid = string(uuid4())
    while orderid in keys(strat.orders)
      orderid = string(uuid4())
    end
    # Store the order
    strat.orders[orderid] = order

    # Push event corresponding to an order ack we would receive from our brokerage/exchange
    Events.push!(
      strat.events,
      OrderAckEvent(
        strat.curtime + 2*strat.options.messagelatency,
        orderid
    ))

    # See if the order would be filled during this bar.
    # If not, then store it as an open order.
    fillsthisbar = tryfillorder!(strat, order)
    if !fillsthisbar
      push!(strat.openorderids, orderid)
    end

    return orderid
  end

  function tryfillorder!(strat::Strategy, order::OT)::Bool where {OT<:Orders.AbstractOrder}
    """NOTE: ASSUMES THAT WE ARE TRYING TO FILL THE ORDER AT THE BEGINNING OF A BAR!"""

    if order.size == 0
      throw("Cannot process an order with `size`=0.")
    end

    genesisdata = peek(strat.options.datareaders[order.assetid])
    open = genesisdata[strat.options.opencol]
    low = genesisdata[strat.options.lowcol]
    high = genesisdata[strat.options.highcol]
    if isa(order, Orders.MarketOrder)
      mid = (low+high)/2
      deltacash = -order.size*mid
      if strat.portfolio.buyingpower + deltacash < 0
        throw(string("Tried to place order ", order, " at price ", mid, " but there is only ", strat.portfolio.buyingpower, " of cash."))
      end
      Events.push!(strat.events, OrderFillEvent(
        strat.curtime + strat.options.messagelatency, # fills as soon as it gets to the exchange
        order,
        deltacash,
        order.size
      ))
      return true
    elseif isa(order, Orders.LimitOrder)
      executionprice = 0
      limitbuyfills = order.size > 0 && order.extremum >= low
      limitsellfills = order.size < 0 && order.extremum <= high
      if limitbuyfills
        executionprice = min(open, order.extremum)
      elseif limitsellfills
        executionprice = max(open, order.extremum)
      end

      if limitbuyfills || limitsellfills
        deltacash = -order.size*executionprice
        if strat.portfolio.buyingpower + deltacash < 0
          throw(string("Tried to place order ", order, " at price ", mid, " but there is only ", strat.portfolio.buyingpower, " of cash."))
        end
        # say it executes at a random time within the bar
        executiontime = randomtimeininterval(strat.curtime+strat.options.messagelatency, curbarendtime(strat)+strat.options.messagelatency) #
        Events.push!(strat.events, OrderFillEvent(
          executiontime,
          order,
          deltacash,
          order.size
        ))
        return true
      else
        return false
      end
    else
      throw(string("Cannot recognize order of type, `", typeof(order), "`."))
      return false
    end
  end

  function tryfillorders!(strat::Strategy)
    """Function invoked at the beginning of a bar to fill orders on assets
    that will fill during the bar."""
    numorderstocheck = length(strat.openorderids)
    numorderschecked = 0
    while numorderschecked < numorderstocheck
      toporderid = popfirst!(strat.openorderids)
      orderfilled = tryfillorder(strat, strat.orders[toporderid])
      if !orderfilled
        push!(strat.openorderids, toporderid)
      end
      numorderschecked += 1
    end
  end

  function updateportfolio!(strat::Strategy, event::ET) where {ET<:AbstractOrderEvent}
    """Modify the portfolio to reflect an order event. This is handled
    automatically, so users do not need to update the portfolio
    within their own `onorderevent` functions.
    """
    # Check if the portfolio actually needs to be updated
    if isa(event, OrderFillEvent)
      assetid = event.order.assetid
      # Update the equity values
      if !haskey(strat.portfolio.equity, assetid)
        strat.portfolio.equity[assetid] = 0
      end
      strat.portfolio.equity[assetid] += event.deltaequity

      # Update the cash values
      strat.portfolio.buyingpower += event.deltacash

      # Update the value of the portfolio
      assetprices = data(strat, strat.options.closecol) # get the most recent value for the close of the bar; this isn't a perfect estimator of current value, since there's some lag
      equityvalue = 0
      for assetid in keys(strat.portfolio.equity)
        equityvalue += strat.portfolio.equity[assetid] * assetprices[assetid]
      end
      strat.portfolio.value = strat.portfolio.buyingpower + equityvalue
    end
  end

  ## Methods related to event handling ##
  function onnewbarevent!(strat::Strategy, event::NewBarEvent)
    realstart = now()
    newbar!(strat.lattice, event.genesisdata) # run a bar on the CalcLattice
    realend = now()

    computationtime = realend - realstart
    timeaftercomputation = strat.curtime + computationtime
    if timeaftercomputation > curbarendtime(strat)
      throw(string("Lattice computations (i.e. computations on pre-defined",
      " fields) took more than the available time in the bar to compute fields."))
    end

    Events.push!(strat.events, FieldCompletedProcessingEvent(timeaftercomputation))
  end

  function processevent!(strat::Strategy, event::T) where {T<:AbstractEvent}
    """Delegate particular events to their relevant event handlers."""
    strat.curtime = event.time
    log(strat, "Processing `$(typeof(event))` event.", INFO)

    if isa(event, NewBarEvent)
      onnewbarevent!(strat, event)
    elseif isa(event, FieldCompletedProcessingEvent)
      strat.options.ondataevent!(strat, event)
    elseif isa(event, AbstractOrderEvent)
      log(strat, "Order Event: $event.", TRANSACTIONS)
      updateportfolio!(strat, event) # update the portfolio as soon as we see an order event
      strat.options.onorderevent!(strat, event)
    end
  end

  ## Higher level methods used for running a backtest ##
  function runnextbar!(strat::Strategy, genesisfielddata::Dict{AssetId, Dict{FieldId, T}}) where {T<:Any}
    # 1. Account for it being a new bar
    # 2. Push a new data event
    # 3. Execute events until either there's no more time in the bar OR there
    #    are no more events to run.

    # Account for new bar
    strat.curbarindex += 1
    strat.curtime = genesisfielddata[strat.assetids[1]][strat.options.datetimecol]

    # Fill all of the orders for the last bar; NOTE: this works due to a weird
    # loophole from the state of the program. `runnextbar` is only invoked from
    # inside `run`. Before calling `runnextbar!`, `run` will call `loadgenesisdata!`,
    # which moves the datareaders forward a bar. This means that the current
    # `peeking` bar is in fact the bar we are on. For example, if we peek into
    # a minute-level datareader at 11:33 AM, we will see the bar data for
    # 11:33-11:34 AM. Thus, we can call `tryfillorders!` at this point.
    tryfillorders!(strat)

    # Push the data to the queue
    Events.push!(strat.events, NewBarEvent(
      strat.curtime + strat.options.datadelay,
      genesisfielddata
    ))

    while !Events.empty(strat.events) && Events.peek(strat.events).time < curbarendtime(strat)
      event = Events.pop!(strat.events)
      processevent!(strat, event)
    end
    log(strat, string("Finished running bar #", strat.curbarindex, "."), INFO)
  end

  function peekgenesisdata(strat::Strategy)
    genesisfielddata = Dict{AssetId, Dict{FieldId, Any}}()
    for assetid in assetids
      genesisfielddata[assetid] = peek(strat.options.datareaders[assetid])
    end
    return genesisfielddata
  end

  function loadgenesisdata!(strat::Strategy)::Dict{AssetId, Dict{FieldId, Any}}
    # Initialize genesis field data array
    uniquedatetimes = Set([])
    genesisfielddata = Dict{AssetId, Dict{FieldId, Any}}()
    for assetid in strat.assetids
      genesisassetfielddata = popfirst!(strat.options.datareaders[assetid])
      datetime = genesisassetfielddata[strat.options.datetimecol]
      union!(uniquedatetimes, [datetime])
      # println(uniquedatetimes)
      if length(uniquedatetimes) != 1
        println(uniquedatetimes)
        log(strat, "Not all datetimes are unique; consider investigating the data sources. Bear in mind that all data sources must have the same bar start times after the given backtest start time.", DEBUG)
        throw("")
      else
        genesisfielddata[assetid] = genesisassetfielddata
      end
    end
    return genesisfielddata
  end

  function onend(strat::Strategy)
    # for ago in length(strat.lattice.recentbars)-1:-1:0
    for ago in 1:-1:0
      println(data(strat, ago))
    end

    message = string(
      "Completed running backtest after ", strat.curbarindex, " bars. ",
      "The final portfolio value is ", strat.portfolio.value, ", with buyingpower=",
      strat.portfolio.buyingpower, ", and the following holdings: ", strat.portfolio.equity, "."
    )

    log(strat, message, NOVERBOSITY)
  end

  ## Main interface functions ##
  ### Main Function ###
  function run(stratoptions::StrategyOptions)
    # Build the strategy
    strat = Strategy(stratoptions)

    # Run the strategy
    while curbarendtime(strat) < strat.options.endtime
      genesisfielddata = loadgenesisdata!(strat)
      runnextbar!(strat, genesisfielddata)
    end

    # Finish the backtest
    onend(strat)
  end

  export run, data, numbarsavailable
end
