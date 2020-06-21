module Backtest
  using Dates: DateTime, TimeType
  using Dates
  using Ids: AssetId, FieldId
  using AbstractFields: AbstractFieldOperation
  using Events: EventQueue, AbstractEvent, NewBarEvent, FieldCompletedProcessingEvent
  using Events
  using Engine: CalcLattice, addfields!, newbar!
  using DataReaders: AbstractDataReader, fastforward!, popfirst!

  ## Type definitions ##
  abstract type AbstractVerbosity end
  abstract type INFO <: AbstractVerbosity end
  abstract type DEBUG <: INFO end
  abstract type WARNING <: DEBUG end
  abstract type NOVERBOSITY <: WARNING end

  # TODO: ondataevent!, onorderevent! defaults
  struct StrategyOptions
    datareaders::Vector{DR} where {DR<:AbstractDataReader}
    fieldoperations::Vector{FO} where {FO<:AbstractFieldOperation}
    numlookbackbars::Integer
    start::ST where {ST<:Dates.TimeType}
    endtime::ET where {ET<:Dates.TimeType}
    barsize::BT where {BT<:Dates.Period}
    verbosity::DataType
    datadelay::DDT where {DDT<:Dates.Period}
    ondataevent!::TODE where {TODE<:Function}
    onorderevent!::TOE where {TOE<:Function}
  end
  function StrategyOptions(;
                          datareaders::Vector{DR},
                          fieldoperations::Vector{FO},
                          start::ST,
                          endtime::ET,
                          numlookbackbars::Integer=-1,
                          barsize::BT=Day(1),
                          verbosity::Type=NOVERBOSITY,
                          datadelay::DDT=1,
                          ondataevent::Function=(dataevent->nothing),
                          onorderevent::Function=(orderevent->nothing)
                          ) where { DR<:AbstractDataReader, FO<:AbstractFieldOperation,
                          ST<:Dates.TimeType, ET<:Dates.TimeType, BT<:Dates.TimePeriod,
                          DDT<:Dates.Period }
    return StrategyOptions(datareaders, fieldoperations, numlookbackbars,
      start, endtime, barsize, verbosity, datadelay, ondataevent, onorderevent
    )
  end

  mutable struct Strategy
    options::StrategyOptions
    events::EventQueue
    assetids::Vector{String}
    lattice::CalcLattice
    curtime::DateTime
    curbarindex::Integer
  end
  function Strategy(options::StrategyOptions)
    """User-facing constructor."""
    # Prepare the data readers
    preparedatareaders!(options.datareaders, options.start)

    # Prepare the lattice
    assetids = map( (datareader -> datareader.assetid), options.datareaders)
    lattice = CalcLattice(options.numlookbackbars, assetids)
    addfields!(lattice, options.fieldoperations)
    return Strategy(
      options,
      EventQueue(),
      assetids, # assetids
      lattice,
      options.start,
      0
    )
  end

  ## Utility functions ##
  function log(strat::Strategy, message::String, verbosity::Type)
    if verbosity <: strat.options.verbosity
      println(string(strat.curtime, " ~~~~ ", message))
    end
  end

  function preparedatareaders!(datareaders::Vector{DR}, time::DateTime) where {DR<:AbstractDataReader}
    if length(datareaders) == 0
      throw(string("No datareaders specified. At least one datareader must be",
      " specified in order to run a backtest."))
    end
    map( (datareader -> fastforward!(datareader, time)), datareaders )
  end

  time(strat::Strategy) = strat.curtime # getter for the current time in backtest-land (not the actual current time outside the program)

  curbarstarttime(strat::Strategy) =
    strat.options.start + (strat.curbarindex - 1) * strat.options.barsize

  nextbarstarttime(strat::Strategy) = curbarstarttime(strat) + strat.options.barsize

  function onnewbarevent!(strat::Strategy, event::NewBarEvent)
    realstart = now()
    newbar!(strat.lattice, event.genesisdata) # run a bar on the CalcLattice
    realend = now()

    computationtime = realend - realstart
    timeaftercomputation = strat.curtime + computationtime
    if timeaftercomputation > nextbarstarttime(strat)
      # TODO: it may be the case that someone wants to process something that
      # takes longer than a bar, so consider changing this to a "If the
      # computation takes longer than some predefined timeout value, throw
      # an exception"
      throw(string("Lattice computations (i.e. computations on pre-defined",
      " fields) took more than the available time in the bar to compute fields."))
    end

    Events.push!(strat.events, FieldCompletedProcessingEvent(timeaftercomputation))

  end

  function processevent!(strat::Strategy, event::T) where {T<:AbstractEvent}
    strat.curtime = event.time

    if isa(event, NewBarEvent)
      onnewbarevent!(strat, event)
    elseif isa(event, FieldCompletedProcessingEvent)
      strat.options.ondataevent!(strat, event)
    elseif isa(event, OrderEvent)
      strat.options.onorderevent!(strat, event)
    end
  end

  function runnextbar!(strat::Strategy, genesisfielddata::Dict{AssetId, Dict{FieldId, T}}) where {T<:Any}
    # 1. Account for it being a new bar
    # 2. Push a new data event
    # 3. Execute events until either there's no more time in the bar OR there
    #    are no more events to run.

    # Account for new bar
    strat.curbarindex += 1
    strat.curtime = curbarstarttime(strat)

    # Push the data to the queue
    Events.push!(strat.events, NewBarEvent(
      strat.curtime + strat.options.datadelay,
      genesisfielddata
    ))

    while !Events.empty(strat.events) && Events.peek(strat.events).time < nextbarstarttime(strat)
      event = Events.pop!(strat.events)
      log(strat, "Processing event!", INFO)
      processevent!(strat, event)
    end
    log(strat, string("Finishing running bar #", strat.curbarindex, "."), INFO)

  end

  function loadgenesisdata!(strat::Strategy)::Dict{AssetId, Dict{FieldId, Any}}
    # Initialize genesis field data array
    genesisfielddata = Dict{AssetId, Dict{FieldId, Any}}()
    for datareader in strat.options.datareaders
      genesisfielddata[datareader.assetid] = popfirst!(datareader)
    end

    return genesisfielddata
  end
  nextbarexists(strat::Strategy) = (nextbarstarttime(strat) < strat.options.endtime)

  ## Main interface functions ##
  function run(stratoptions::StrategyOptions)
    # Build the strategy
    strat = Strategy(stratoptions)
    # Run the strategy
    while nextbarexists(strat)
      genesisfielddata = loadgenesisdata!(strat)
      runnextbar!(strat, genesisfielddata)
    end
    
    log(strat, string("Completed running backtest after ", strat.curbarindex, " bars."), NOVERBOSITY)
  end
end
