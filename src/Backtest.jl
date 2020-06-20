module Backtest
  module Helpers
    using Dates: DateTime, format
    using AbstractFields: AbstractFieldOperation
    using DataReader: AbstractDataReader, fastforward!

    abstract type AbstractVerbosity end
    abstract type INFO <: AbstractVerbosity end
    abstract type DEBUG <: INFO end
    abstract type WARNING <: DEBUG end

    struct StrategyOptions
      datareaders::Vector{DR} where {DR<:AbstractDataReader}
      fieldoperations::Vector{AbstractFieldOperation}
      numlookbackbars::Integer
      start::DateTime
      barsize::DateTime
      verbosity::V where {V<:AbstractVerbosity}
      genesisdatathreshproportion::F where {F<:AbstractFloat}
      datadelayseconds::F where {F<:AbstractFloat}
    end

    function preparedatareaders!(datareaders::Vector{DR}, time::DateTime) where {DR<:AbstractDataReader}
      map( (datareader -> fastforward!(datareader, time)), datareaders )
    end

    function log(strat, message::String, verbosity::AbstractVerbosity)
      if strat.useroptions.verbosity <: verbosity
        println(string(strat.curtime, "~~~~", message))
      end
    end
  end

  ## Strategy definition and functions ##
  module Strategy_
    using Dates: DateTime
    using ..Helpers: StrategyOptions, AbstractVerbosity, preparedatareaders!, log,
      INFO, DEBUG, WARNING
    using Events: EventQueue, AbstractEvent, NewBarEvent
    using ID: AssetId, FieldId
    using Engine: CalcLattice
    using DataReader: AbstractDataReader
    
    struct Strategy
      options::StrategyOptions
      events::EventQueue
      assetids::Vector{AssetId}
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

    time(strat::Strategy) = strat.curtime # getter for the current time in backtest-land (not the actual current time outside the program)

    # TODO: loadgenesisdata

    curbarstarttime(strat::Strategy) =
      strat.options.start + (strat.curbarindex - 1)* strat.options.barsize

    nextbarstarttime(strat::Strategy) = curbarstarttime() + strat.useroptions.barsize

    # TODO: ondataevent!, onorderevent! defaults
    function onnewbarevent!(strat::Strategy, event::NewBarEvent)
      realstart = now()
      newbar!(strat.lattice, event.genesisdata) # run a bar on the CalcLattice
      realend = now()

      computationtime = realend - realstart
      timeaftercomputation = strat.curtime + computationtime
      if timeaftercomputation > nextbarstarttime(strat)
        # NOTE: it may be the case that someone wants to process something that
        # takes longer than a bar, so consider changing this to a "If the
        # computation takes longer than some predefined timeout value, throw
        # an exception"
        throw(string("Lattice computations (i.e. computations on pre-defined",
        " fields) took more than the available time in the bar to compute fields."))
      end

      push!(strat.events, FieldCompletedProcessingEvent(timeaftercomputation))

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

    function runnextbar!(strat::Strategy, genesisfielddata)
      # 1. Push a new data event
      # 2. Execute events until either there's no more time in the bar OR there
      #    are no more events to run.

      # Account for new bar
      strat.curbarindex += 1
      strat.curtime = curbarstarttime()

      # Push the data to the queue
      push!(strat.events, NewBarEvent(
        curtime + strat.options.datadelayseconds,
        genesisfielddata
      ))

      while peek(strat.events).time < nextbarstarttime() && !empty(strat.event)
        event = pop!(strat.events)
        log(strat, "Processing bar!", INFO)
        processevent!(strat, event)
      end
      log(strat, string("Finishing running bar #", strat.curbarindex, "."), INFO)

    end

    function run(strat::Strategy)
      # Run the strategy
      while nextbarexists(strat)
        proportionassetsloadedwell, genesisfielddata = loadgenesisdata(strat)
        if proportionassetsloadedwell >= 1.0
          runnextbar!(strat, genesisfielddata)
        else
          log(strat, string("Stopped running backtest because the proportion ",
            "of correctly loaded assets was ", proportionassetsloadedwell ,
            "and the threshold is ", strat.options.genesisdatathreshproportion, "."),
            DEBUG)
        end
      end
      log(strat, string("Completed running backtest."), INFO)
    end
  end
end
end
