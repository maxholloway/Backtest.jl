module Backtest
  module Ids
    const AssetId = String
    const FieldId = String
    const OrderId = String
  end # module

  module Exceptions
    import Dates: TimeType
    import ..Ids: AssetId

    struct AbstractMethodError <: Exception
      msg::String
      AbstractMethodError(cls::Type, method::Function) = new(
        string("Cannot run  method ", method, " with abstract class ", cls, ".")
      )
    end

    struct DateTooEarlyError <: Exception
      msg::String
      function DateTooEarlyError(requestedtime::T, assetid::AssetId ) where {T<:TimeType}
        return new( string("The requested time, ", requestedtime, ", is before the first time", " in ", assetid, "."))
      end
    end

    struct DateTooFarOutError <: Exception
      msg::String
      DateTooFarOutError(requestedtime::T, assetid::AssetId) where {T<:TimeType} = new(
        string("There is not enough data in ", assetid, " to access ", requestedtime, ".")
      )
    end
  end # module

  module AbstractFields
    import ..Ids: AssetId, FieldId
    import ..Exceptions: AbstractMethodError

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
      throw(AbstractMethodError(AbstractWindowFieldOperation, dofieldop))
    end

    """
      `AbstractCrossSectionalFieldOperation` is the mother of all concrete
      CrossSectionalFieldOperation types.

      Required subtypes:
      1. All subtypes needed for `AbstractDownstreamFieldOperation`.
    """
    abstract type AbstractCrossSectionalFieldOperation <: AbstractDownstreamFieldOperation end

    function dofieldop(abstractcrosssectionalfieldoperation::AbstractCrossSectionalFieldOperation, data::Dict{AssetId, Any})::Dict{AssetId, Any}
      throw(AbstractMethodError(AbstractCrossSectionalFieldOperation, dofieldop))
    end

    export AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
  end # module

  module ConcreteFields
    import ..Ids: AssetId, FieldId
    import ..AbstractFields: AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
    import Statistics: mean, std
    import NamedArrays: NamedArray, names


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
      zscores = [(x-mu)/sigma for x in assetdata]
      zscores = NamedArray(zscores, (names(assetdata, 1),))
      return zscores
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

  module Engine
    import NamedArrays: NamedArray
    import ..Ids: AssetId, FieldId
    import ..AbstractFields: AbstractFieldOperation, AbstractGenesisFieldOperation, AbstractWindowFieldOperation, AbstractCrossSectionalFieldOperation
    import ..ConcreteFields: dofieldop
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
      # WARNING: If this ends up being parallelized, consider placing a lock here to make Counter thread-safe
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

    function tryaccessago(lattice::CalcLattice, ago::Integer)
      if (ago > numbarsavailable(lattice)) || (ago < 0) || ((lattice.numbarsstored!=-1) && (ago > lattice.numbarsstored))
        throw("Invalid `ago`: $ago, while lattice is only on the $(lattice.curbarindex), index.")
      end
    end

    function getnbaragodata(lattice::CalcLattice, ago::Integer)::BarLayer
      tryaccessago(lattice, ago)
      mostrecentbarindex = length(lattice.recentbars)
      return lattice.recentbars[mostrecentbarindex-ago]
    end

    function getcurrentbar(lattice::CalcLattice)::BarLayer
      return getnbaragodata(lattice, 0)
    end

    function updatebars!(lattice::CalcLattice)
      """Update the `recentbars` field in preparation for the next bar."""
      # see documentation for `CalcLattice.numbarsstored`
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

    function compute!(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)
      """Computes a window operation node.
      """
      windowfieldoperation = lattice.fieldids_to_ops[fieldid]
      # Get data for the window operation (time is the free variable)
      windowdata = getwindowdata(lattice, windowfieldoperation, assetid)

      # Perform the window operation
      value = dofieldop(windowfieldoperation, windowdata)

      # Set value for this node
      insertnode!(lattice, assetid, fieldid, value)
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
    function newbar!(lattice::CalcLattice, newbardata::Dict{AssetId, Dict{FieldId, T}}) where {T}

      lattice.numcompletedassets = Counter{FieldId}()
      lattice.curbarindex += 1
      updatebars!(lattice)
      for assetid in lattice.assetids
        if !(assetid in keys(newbardata))
          throw("Asset id ``$assetid` was expected, but is not among the asset ids in the new bar data.")
        end
        for fieldid in lattice.genesisfieldids
          if !(fieldid in keys(newbardata[assetid]))
            throw("Field id ``$fieldid` was expected, but is not among the field ids in the new bar data.")
          end

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

    function numbarsavailable(lattice::CalcLattice)
      return lattice.recentbars |> length
    end

    function getalldata(lattice::CalcLattice)::Vector{NamedArray}
      """Returns a vector of (assetid, fieldid)->value pairs. The entries in the vector are in
      chronological order, meaning that the last entry will represent the most recent bar."""
      return map((barlayer -> barlayer.bardata), lattice.recentbars)
    end

    function data(lattice::CalcLattice, ago::Integer)::NamedArray
      """Gets (assetid, fieldid)->value pairs for `ago` bars ago; if `ago=0`,
      this gets the previous bar's data."""
      tryaccessago(lattice, ago)
      return lattice.recentbars[numbarsavailable(lattice) - ago].bardata
    end

    function data(lattice::CalcLattice, ago::Integer, fieldid::FieldId)::NamedArray
      """Gets (assetid)->value pairs for `ago` bars ago for a particular field;
      if ago=0, then this is equivalent to data(strat, fieldid)."""
      tryaccessago(lattice, ago)
      return data(lattice, ago)[:, fieldid]
    end

    function data(lattice::CalcLattice, ago::Integer, assetid::AssetId, fieldid::FieldId)
      """Gets the value for a particular field for a particular asset on a particular bar; if
      ago=0, then this is equivalent to data(strat, assetid, fieldid)."""
      tryaccessago(lattice, ago)
      return data(lattice, ago)[assetid, fieldid]
    end

    function data(lattice::CalcLattice)::NamedArray
      """Gets (assetid, fieldid)->value pairs for the previous bar.
      For example, if the time between bars is 1 minute, and the current time
      is 11:33:25 (HH:MM:SS), then this would give OHLCV data from
      11:32:00-11:32:59.999... . WE CANNOT ACCESS DATA FOR THE CURRENT BAR,
      SINCE IT IS NOT COMPLETED YET (e.g. cannot access this bar's open price)."""
      return data(lattice, 0)
    end

    function data(lattice::CalcLattice, fieldid::FieldId)::NamedArray
      """Gets assetid->value pairs for the previous bar."""
      return data(lattice, 0, fieldid)
    end

    function data(lattice::CalcLattice, assetid::AssetId, fieldid::FieldId)
      """Gets value for a particular field for a particular asset on the previous bar."""
      return data(lattice, 0, assetid, fieldid)
    end

    export newbar!, addfields!, getalldata, data, numbarsavailable
  end # module

  module DataReaders
    import Dates: TimeType, DateTime, DateFormat
    import CSV: File
    import DataFrames: DataFrame, nrow, DataFrame!
    import ..Exceptions: AbstractMethodError, DateTooEarlyError, DateTooFarOutError
    import ..Ids: AssetId, FieldId
    import Base.copy

    abstract type AbstractDataReader end

    mutable struct InMemoryDataReader <: AbstractDataReader
      """Stores all asset data in memory."""
      assetid::AssetId
      data::DataFrame
      datetimecol::AS where {AS<:AbstractString}
    end

    mutable struct PerFileDataReader <: AbstractDataReader
      """Stores a single file in memory at a time."""
      assetid::AssetId
      sources::Vector{ST} where {ST<:AbstractString}
      datetimecol::DTCT where {DTCT<:AbstractString}
      dtfmt::FT where {FT<:AbstractString}
      delim::Char
      curfiledata::DataFrame
    end

    module Internal
      using ...Ids: FieldId
      using ..DataReaders: InMemoryDataReader, PerFileDataReader
      using DataFrames: DataFrame, nrow, DataFrame!
      using CSV: File
      function step!(datareader::InMemoryDataReader)
        datareader.data = datareader.data[2:nrow(datareader.data), :]
      end

      function step!(datareader::PerFileDataReader)
        prepfilefornext!(datareader)
        datareader.curfiledata = datareader.curfiledata[2:nrow(datareader.curfiledata), :]
      end

      function prepfilefornext!(datareader::PerFileDataReader)
        """Since the PerFileDataReader iterates over a particular file
        (`curfiledata`) and potentially many files (`sources`), we must
        ensure that if we've complete a single file, we update `curfiledata`
        with the data from the next file."""
        if isempty(datareader.curfiledata) && isempty(datareader.sources)
          throw("Attempted to read data from an empty datareader.")
        elseif isempty(datareader.curfiledata)
          # load next file of data
          nextfile = popfirst!(datareader.sources)
          datareader.curfiledata = File(nextfile, delim=datareader.delim) |> DataFrame!
        end
      end

      function peek(df::DataFrame)
        """Return the top row of a dataframe in Dict format."""
        toprow::NamedTuple = df[1, :]
        nametovalues::Dict{FieldId, Any} = Dict{FieldId, Any}()
        for kvpair in zip(fieldnames(typeof(toprow)), toprow)
          nametovalues[string(kvpair[1])] = kvpair[2]
        end
        return nametovalues
      end

    end # module

    using .Internal

    function InMemoryDataReader(assetid::String, sources::Vector{S};
        datetimecol::String="datetime",
        dtfmt::String="yyyy-mm-ddTHH:MM:SS",
        delim::Char=',')::InMemoryDataReader where {S<:AbstractString}
      if length(sources) == 0
        throw("`sources` must have at least one element.")
      end

      # Read first source, then append all others to the first.
      # alldata = read(sources[1], delim=delim, copycols=true)
      alldata = File(sources[1], delim=delim) |> DataFrame!
      for i = 2:length(sources)
        # append!(alldata, read(sources[i], delim=delim), copycols=true)
        append!(alldata, File(sources[i], delim=delim) |> DataFrame!)
      end

      if size(alldata)[1] == 0
        throw("No data was parsed!")
      elseif isa(alldata[1, datetimecol], AbstractString)
        alldata[!, datetimecol] = DateTime.(alldata[:, datetimecol], DateFormat(dtfmt))
      elseif !isa(alldata[1, datetimecol], TimeType)
        throw("The given datetime column, $datetimecol, has values with invalid type '$(typeof(alldata[1, datetimecol]))'.
            A valid type for this column, 'T', would satisfy {T<:Union{AbstractString, Dates.TimeType}}.")
      end

      return InMemoryDataReader(assetid, alldata, datetimecol)
    end

    function PerFileDataReader(assetid::String, sources::Vector{S};
        datetimecol::String="datetime",
        dtfmt::String="yyyy-mm-ddTHH:MM:SS",
        delim::Char=',')::PerFileDataReader where {S<:AbstractString}
      if length(sources) == 0
        throw("`sources` must have at least one element.")
      end
      curfiledata = DataFrame()

      return PerFileDataReader(assetid, Base.copy(sources), datetimecol, dtfmt, delim, curfiledata)
    end

    function InMemoryDataReader(assetid::String, source::String;
        datetimecol::String="datetime",
        dtfmt::String="yyyy-mm-ddTHH:MM:SS",
        delim::Char=',')

        return InMemoryDataReader(assetid, [source];
          datetimecol=datetimecol, dtfmt=dtfmt, delim=delim)
      end

    function PerFileDataReader(assetid::String, source::S;
        datetimecol::String="datetime",
        dtfmt::String="yyyy-mm-ddTHH:MM:SS",
        delim::Char=',')::PerFileDataReader where {S<:AbstractString}
      return PerFileDataReader(assetid, [source]; datetimecol=datetimecol, dtfmt=dtfmt, delim=delim)
    end

    function copy(dr::InMemoryDataReader)
      return InMemoryDataReader(dr.assetid, dr.data, dr.datetimecol)
    end

    function copy(dr::PerFileDataReader)
      return PerFileDataReader(dr.assetid, Base.copy(dr.sources), dr.datetimecol, dr.dtfmt, dr.delim, dr.curfiledata)
    end

    function fastforward!(datareader::DRT, time::T) where {DRT<:AbstractDataReader, T<:TimeType}
      curtime() = peek(datareader)[datareader.datetimecol]
      if empty(datareader)
        throw("`DataReader` has no data.")
      elseif curtime() > time
        throw(DateTooEarlyError(time, datareader.assetid))
      end
      while !empty(datareader) && curtime() < time
        Internal.step!(datareader)
      end

      if empty(datareader)
        throw(DateTooFarOutError(time, datareader.assetid))
      end
    end

    function peek(datareader::InMemoryDataReader)::Dict{FieldId, Any}
      return Internal.peek(datareader.data)
    end

    function peek(datareader::PerFileDataReader)::Dict{FieldId, Any}
      Internal.prepfilefornext!(datareader)
      return Internal.peek(datareader.curfiledata)
    end

    function popfirst!(datareader::InMemoryDataReader)::Dict{FieldId, Any}
      fieldtovalues = peek(datareader)
      delete!(datareader.data, 1)
      return fieldtovalues
    end

    function popfirst!(datareader::PerFileDataReader)::Dict{FieldId, Any}
      fieldtovalues = peek(datareader)
      delete!(datareader.curfiledata, 1)
      return fieldtovalues
    end

    empty(datareader::InMemoryDataReader) = isempty(datareader.data)

    function empty(datareader::PerFileDataReader)
      return isempty(datareader.curfiledata) && isempty(datareader.sources)
    end

    export copy
  end # module

  module Orders
    import ..Ids: AssetId

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
    import Dates: TimeType
    import ..Ids: AssetId, FieldId, OrderId
    import ..Orders: AbstractOrder

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
      orderid::OrderId
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
  import Dates: DateTime, TimeType, Minute, Millisecond, Period,
                TimePeriod, format
  import UUIDs: uuid4
  import NamedArrays: NamedArray
  import .Ids: AssetId, FieldId, OrderId
  import .AbstractFields: AbstractFieldOperation
  import .Events: EventQueue, FieldCompletedProcessingEvent, OrderAckEvent, push!, empty

  using .Orders
  import .Engine: CalcLattice, getalldata, data, numbarsavailable
  import .DataReaders: AbstractDataReader
  import .DataReaders # required in order to resolve `peek` collision

  ## Type Declarations ##
  abstract type AbstractVerbosity end
  abstract type INFO <: AbstractVerbosity end
  abstract type TRANSACTIONS <: INFO end
  abstract type DEBUG <: TRANSACTIONS end
  abstract type WARNING <: DEBUG end
  abstract type NOVERBOSITY <: WARNING end

  struct StrategyOptions
    datareaders::Dict{AssetId, DR} where {DR<:AbstractDataReader}
    fieldoperations::Vector{FO} where {FO<:AbstractFieldOperation}
    numlookbackbars::Integer
    start::ST where {ST<:TimeType}
    endtime::ET where {ET<:TimeType}
    tradinginterval::TTI where {TTI<:Period}
    verbosity::DataType
    datadelay::DDT where {DDT<:Period}
    messagelatency::ODT where {ODT<:Period}
    fieldoptimeout::FOTOT where {FOTOT<:Period}
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
    barstarttimes::Vector{DateTime}
    curbarstarttime::DateTime
    curtime::DateTime
    curbarindex::Integer
  end

  ## Interface Functions (pt. 1) ##
  function getalldata(strat::Strategy)::Vector{NamedArray}
    Engine.getalldata(strat.lattice)
  end

  function data(strat::Strategy, ago::Integer)::NamedArray
    """Gets (assetid, fieldid)->value pairs for `ago` bars ago; if `ago=0`,
    this gets the previous bar's data."""
    return data(strat.lattice, ago)
  end

  function data(strat::Strategy, ago::Integer, fieldid::FieldId)::NamedArray
    """Gets (assetid)->value pairs for `ago` bars ago for a particular field;
    if ago=0, then this is equivalent to data(strat, fieldid)."""
    return data(strat.lattice, ago, fieldid)
  end

  function data(strat::Strategy, ago::Integer, assetid::AssetId, fieldid::FieldId)
    """Gets the value for a particular field for a particular asset on a particular bar; if
    ago=0, then this is equivalent to data(strat, assetid, fieldid)."""
    return data(strat.lattice, ago, assetid, fieldid)
  end

  function data(strat::Strategy)::NamedArray
    """Gets (assetid, fieldid)->value pairs for the previous bar.
    For example, if the time between bars is 1 minute, and the current time
    is 11:33:25 (HH:MM:SS), then this would give OHLCV data from
    11:32:00-11:32:59.999... . WE CANNOT ACCESS DATA FOR THE CURRENT BAR,
    SINCE IT IS NOT COMPLETED YET (e.g. cannot access this bar's open price)."""
    return data(strat.lattice)
  end

  function data(strat::Strategy, fieldid::FieldId)::NamedArray
    """Gets assetid->value pairs for the previous bar."""
    return data(strat.lattice, fieldid)
  end

  function data(strat::Strategy, assetid::AssetId, fieldid::FieldId)
    """Gets value for a particular field for a particular asset on the previous bar."""
    return data(strat.lattice, assetid, fieldid)
  end

  function numbarsavailable(strat::Strategy)
    return numbarsavailable(strat.lattice)
  end

  ### Etc. Function(s) ###
  function log(strat::Strategy, message::String, verbosity::Type)
    if verbosity <: strat.options.verbosity
      time = format(strat.curtime, "yyyy-mm-dd HH:MM:SS.sss")
      println(string(time, " ~~~~ ", message))
    end
  end

  ## End interface functions (pt. 1) ##

  module Internals
    using ...Ids: AssetId, FieldId, OrderId
    using ...AbstractFields: AbstractFieldOperation
    using ...ConcreteFields: Open, High, Low, Close, Volume
    using ...Events: AbstractEvent, NewBarEvent, push!, peek, pop!,
      FieldCompletedProcessingEvent, AbstractOrderEvent, OrderFillEvent,
      EventQueue
    using ...Events
    using ...DataReaders: AbstractDataReader, popfirst!, fastforward!
    import ...DataReaders
    using ...Engine: CalcLattice, newbar!, addfields!
    using ...Orders: AbstractOrder, MarketOrder
    using ....Backtest: INFO, TRANSACTIONS, Strategy, StrategyOptions, Portfolio, log
    using ...Backtest
    using Dates: DateTime, TimeType, datetime2epochms, epochms2datetime, now
    default_ondataevent(strat, event) = nothing
    default_onorderevent(strat, event) = nothing

    function Strategy(options::StrategyOptions)
      """User-facing constructor."""
      # Prepare the data readers
      preparedatareaders!(options.datareaders, options.start, options.datetimecol)

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
        Dict{OrderId, AbstractOrder}(),
        Vector{OrderId}(),
        assetids,
        Portfolio(options.principal),
        lattice,
        Vector{DateTime}(),
        options.start,
        options.start,
        0
      )
    end

    function preparedatareaders!(datareaders::Dict{AssetId, DR}, starttime::DateTime, datetimecol::DTCT) where {DR<:AbstractDataReader, DTCT<:AbstractString}
      """Fast forward each data reader, so that they're all able to read bars from
      the same starting point."""
      if length(keys(datareaders)) == 0
        throw(string("No datareaders specified. At least one datareader must be",
        " specified in order to run a backtest."))
      end

      for assetid in keys(datareaders)
        fastforward!(datareaders[assetid], starttime)
      end
    end


    function runnextbar!(strat::Strategy, genesisfielddata::Dict{AssetId, Dict{FieldId, T}}) where {T<:Any}

      # Account for new bar
      strat.curbarindex += 1
      strat.curbarstarttime = DateTime(genesisfielddata[strat.assetids[1]][strat.options.datetimecol])
      strat.curtime = strat.curbarstarttime

      # Fill all of the orders for the last bar; NOTE: this works due to a weird
      # loophole from the state of the program. `runnextbar` is only invoked from
      # inside `run`. Before calling `runnextbar!`, `run` will call `loadgenesisdata!`,
      # which moves the datareaders forward a bar. This means that the current
      # `peeking` bar is in fact the bar we are on. For example, if we peek into
      # a minute-level datareader at 11:33 AM, we will see the bar data for
      # 11:33-11:34 AM. Thus, we can call `tryfillorders!` at this point.
      tryfillorders!(strat)

      # Push the data to the queue
      push!(strat.events, NewBarEvent(
        strat.curtime + strat.options.datadelay,
        genesisfielddata
      ))

      while !Events.empty(strat.events) && peek(strat.events).time < curbarendtime(strat)
        event = pop!(strat.events)
        processevent!(strat, event)
      end
      Backtest.log(strat, string("Finished running bar #", strat.curbarindex, "."), INFO)
    end

    function loadgenesisdata!(strat::Strategy)::Dict{AssetId, Dict{FieldId, Any}}
      # Initialize genesis field data array
      uniquedatetimes = Set([])
      genesisfielddata = Dict{AssetId, Dict{FieldId, Any}}()
      for assetid in strat.assetids
        genesisassetfielddata = popfirst!(strat.options.datareaders[assetid])
        datetime = genesisassetfielddata[strat.options.datetimecol]
        union!(uniquedatetimes, [datetime])
        if length(uniquedatetimes) != 1
          errormessage = "Not all datetimes are unique; consider investigating the data sources. Bear in mind that all data sources must have the same bar start times after the given backtest start time."
          Backtest.log(strat, "Error occurred: $message", DEBUG)
          throw(message)
        else
          genesisfielddata[assetid] = genesisassetfielddata
        end
      end
      return genesisfielddata
    end

    curbarendtime(strat::Strategy) = strat.curbarstarttime + strat.options.tradinginterval

    function randomtimeininterval(left::LT, right::RT) where {LT<:TimeType, RT<:TimeType}
      leftms = datetime2epochms(left)
      rightms = datetime2epochms(right)
      randms = rand(leftms:rightms)
      return epochms2datetime(randms)
    end

    ### Methods related to event handling ###
    function onnewbarevent!(strat::Strategy, event::NewBarEvent)
      realstart = now()
      newbar!(strat.lattice, event.genesisdata) # run a bar on the CalcLattice
      realend = now()

      computationtime = realend - realstart
      if computationtime > strat.options.fieldoptimeout # TODO: add test that uses 0 second `fieldoptimeout` and ensures that it throws an error
        throw(string("Field operation computations (i.e. computations on pre-defined",
        " fields) took more than the allowed time; consider increasing `fieldoptimeout`",
        " from its current value of $(strat.options.fieldoptimeout)."))
      end

      push!(strat.events, FieldCompletedProcessingEvent(strat.curtime+computationtime))
    end

    function processevent!(strat::Strategy, event::T) where {T<:AbstractEvent}
      """Delegate particular events to their relevant event handlers."""
      strat.curtime = event.time
      Backtest.log(strat, "Processing `$(typeof(event))` event.", INFO)

      if isa(event, NewBarEvent)
        onnewbarevent!(strat, event)
      elseif isa(event, FieldCompletedProcessingEvent)
        strat.options.ondataevent!(strat, event)
      elseif isa(event, AbstractOrderEvent)
        Backtest.log(strat, "Order Event: $event.", TRANSACTIONS)
        updateportfolio!(strat, event) # update the portfolio as soon as we see an order event
        strat.options.onorderevent!(strat, event)
      end
    end

    function tryfillorder!(strat::Strategy, order::OT)::Bool where {OT<:AbstractOrder}
      """NOTE: ASSUMES THAT WE ARE TRYING TO FILL THE ORDER AT THE BEGINNING OF A BAR!"""
      """Returns true iff the order is filled before then endo of the current bar."""
      # TODO: account for transaction cost
      if order.size == 0
        throw("Cannot process an order with `size`=0.")
      end

      genesisdata = DataReaders.peek(strat.options.datareaders[order.assetid])
      open = genesisdata[strat.options.opencol]
      low = genesisdata[strat.options.lowcol]
      high = genesisdata[strat.options.highcol]
      if isa(order, MarketOrder)
        mid = (low+high)/2
        deltacash = -order.size*mid
        if strat.portfolio.buyingpower + deltacash < 0
          throw(string("Tried to place order $order at price $mid, but there is only $(strat.portfolio.buyingpower) of buying power."))
        end
        push!(strat.events, OrderFillEvent(
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
            throw(string("Tried to place order $order at price $mid, but there is only $(strat.portfolio.buyingpower) of buying power."))
          end
          # say it executes at a random time within the bar
          executiontime = randomtimeininterval(strat.curtime+strat.options.messagelatency, curbarendtime(strat)+strat.options.messagelatency) #
          push!(strat.events, OrderFillEvent(
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
        throw(string("Cannot recognize order of type, `$(typeof(order))`."))
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
        # WARNING: uses `data`, so `data` must be above in the current file
        assetprices = data(strat, strat.options.closecol) # get the most recent value for the close of the bar; this isn't a perfect estimator of current value, since there's some lag
        equityvalue = 0
        for assetid in keys(strat.portfolio.equity)
          equityvalue += strat.portfolio.equity[assetid] * assetprices[assetid]
        end
        strat.portfolio.value = strat.portfolio.buyingpower + equityvalue
      end
    end
  end

  # TODO: replace with an arg in `StrategyOptions`
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

  using .Internals

  ### Main Function ###
  function StrategyOptions(;
                          datareaders::Dict{AssetId, DR}, # data source for each asset
                          fieldoperations::Vector{FO},    # field operations to be performed
                          start::ST,                      # start time for the backtest (this is the DateTime of the first bar of data to be read; actions start one bar later)
                          endtime::ET,                    # end time for the backtest
                          numlookbackbars::Integer=-1,    # number of backtest bars to store; if -1, then all data is stored; if space is an issue, this can be changed to a positive #. However, this will limit how much data can be accessed.
                          tradinginterval::TTI=Minute(390), # how much time there is between the start of a bar
                          verbosity::Type=NOVERBOSITY,     # how much verbosity the backtest should have; INFO gives the most messages, and NOVERBOSITY gives the fewest
                          datadelay::DDT=Millisecond(100), # how much time transpires at the beginning of a bar before data is received; e.g. if this is 5 seconds, then data will be `received` by the backtest 5 seconds after the bar starts.
                          messagelatency::ODT=Millisecond(100), # how much time it takes to transmit a message to a brokerage/exchange
                          fieldoptimeout::FOTOT=Millisecond(100), # how much time until the field operation computatio times out; note that field operations are computed before the user receives data
                          datetimecol::String="datetime", # name of datetime column
                          opencol::String="open",         # name of open column
                          highcol::String="high",         # name of high column
                          lowcol::String="low",           # name of low column
                          closecol::String="close",       # name of close column
                          volumecol::String="volume",     # name of volume column
                          ondataevent::Function=Internals.default_ondataevent, # user-defined function that performs logic when data is received
                          onorderevent::Function=Internals.default_onorderevent, # user-defined function that performs logic when an order event is received
                          principal::PT=100_000           # starting amount of buying power; in many cases this will be interpreted as a starting cash value
                          ) where { DR<:AbstractDataReader, FO<:AbstractFieldOperation,
                          ST<:TimeType, ET<:TimeType, TTI<:TimePeriod,
                          DDT<:Period, ODT<:Period, FOTOT<:Period, PT<:Number }
    return StrategyOptions(datareaders, fieldoperations, numlookbackbars,
      start, endtime, tradinginterval, verbosity, datadelay, messagelatency, fieldoptimeout,
      datetimecol, opencol, highcol, lowcol, closecol, volumecol,  ondataevent,
      onorderevent, principal
    )
  end

  function run(stratoptions::StrategyOptions)::Strategy
    # Build the strategy
    strat = Strategy(stratoptions)

    # Run the strategy
    while Internals.curbarendtime(strat) < strat.options.endtime
      genesisfielddata = Internals.loadgenesisdata!(strat)
      Internals.runnextbar!(strat, genesisfielddata)
    end
    onend(strat)
    # Finish the backtest
    return strat
  end

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
    push!(
      strat.events,
      OrderAckEvent(
        strat.curtime + 2*strat.options.messagelatency,
        orderid
    ))

    # See if the order would be filled during this bar.
    # If not, then store it as an open order.
    fillsthisbar = Internals.tryfillorder!(strat, order)
    if !fillsthisbar
      push!(strat.openorderids, orderid)
    end

    return orderid
  end

  module Utils
    import ..Ids: AssetId, FieldId
    import ..AbstractFields: AbstractFieldOperation
    import ..DataReaders: fastforward!, popfirst!, AbstractDataReader, peek
    import ..DataReaders
    import ...Backtest: Strategy, numbarsavailable, data, log, NOVERBOSITY, run, StrategyOptions, getalldata
    import JSON: json
    import DataStructures: OrderedDict
    import Dates: TimeType, DateTime, TimePeriod, Second

    # Logic for crossover events
    function _cross(strat::Strategy, assetid::AssetId, fielda::FieldId, fieldb::FieldId, over::Bool)::Bool
      """Determines if field `fielda` has "crossed over" field `fieldb` in the most recent
      bar. If `over`, then this will return true if fields `a` and `b` are equal, and then `a`
      moves higher than `b`. If not `over`, this will return true if fields `a`
      and `b` are equal, and then `a` moves lower than `b`. This ensures that any
      cross over or cross under will be discovered if this function is run on each
      bar."""
      if numbarsavailable(strat) >= 2
        (prepreva, preprevb) = data(strat, 1, assetid, fielda), data(strat, 1, assetid, fieldb)
        (preva, prevb) = data(strat, 0, assetid, fielda), data(strat, 0, assetid, fieldb)
        if over
          return (prepreva <= preprevb) && (preva > prevb)
        else
          return (prepreva >= preprevb) && (preva < prevb)
        end
      else
        return false
      end
    end

    function crossover(strat::Strategy, assetid::AssetId, fielda::FieldId, fieldb::FieldId)
      return _cross(strat, assetid, fielda, fieldb, true)
    end

    function crossunder(strat::Strategy, assetid::AssetId, fielda::FieldId, fieldb::FieldId)
      return _cross(strat, assetid, fielda, fieldb, false)
    end

    # Logic for writing data to a JSON file
    function writejson(outputfile::OFT;
        datareaders::Dict{AssetId, DR}, # data source for each asset
        fieldoperations::Vector{FO},    # field operations to be performed
        start::ST,                      # start time for the backtest (this is the DateTime of the first bar of data to be read; actions start one bar later)
        endtime::ET,                    # end time for the backtest
        tradinginterval::TTI=Minute(390), # how much time there is between the start of a bars
        datetimecol::String="datetime", # name of datetime column
        opencol::String="open",         # name of open column
        highcol::String="high",         # name of high column
        lowcol::String="low",           # name of low column
        closecol::String="close",       # name of close column
        volumecol::String="volume",     # name of volume column
        ) where { OFT<:AbstractString, DR<:AbstractDataReader,
        FO<:AbstractFieldOperation, ST<:TimeType, ET<:TimeType, TTI<:TimePeriod}


      # DataReader copy to be used later
      adatareaderkey = pop!(Set(keys(datareaders)))
      adatareader = DataReaders.copy(datareaders[adatareaderkey])

      # Run the empty backtest with all bars stored, no verbosity, no latency, and no principal
      stratoptions = StrategyOptions(
        datareaders=datareaders,
        fieldoperations=fieldoperations,
        numlookbackbars=-1,
        start=start,
        endtime=endtime,
        tradinginterval=tradinginterval,
        verbosity=NOVERBOSITY,
        datadelay=Second(0),
        messagelatency=Second(0),
        datetimecol=datetimecol,
        opencol=opencol,
        highcol=highcol,
        lowcol=lowcol,
        closecol=closecol,
        volumecol=volumecol,
        principal=0
      )
      completedstrat = run(stratoptions)
      allstratdata = getalldata(completedstrat)


      fastforward!(adatareader, start)

      ## Iterate over each date (a do-while loop)
      alljsondata = OrderedDict{DateTime, Dict{AssetId, Dict{FieldId, Any}}}()
      curbarindex = 1
      for curbarindex in 1:length(allstratdata)
        dt = popfirst!(adatareader)[datetimecol]
        if dt >= endtime
          break
        else
          thisbardata = allstratdata[curbarindex]
          alljsondata[dt] = Dict{AssetId, Dict{FieldId, Any}}()
          for assetid in names(thisbardata, 1)
            alljsondata[dt][assetid] = Dict{FieldId, Any}()
            for fieldid in names(thisbardata, 2)
              alljsondata[dt][assetid][fieldid] = thisbardata[assetid, fieldid]
            end
          end
          curbarindex += 1
        end
      end

      # Write all data JSON object to the given file
      jsonstring = json(alljsondata)
      open(outputfile, "w") do f
        write(f, jsonstring)
      end

      return
    end
  end # module

  export StrategyOptions, run, order!, getalldata, data, numbarsavailable, log
end
