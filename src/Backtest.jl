module Backtest
  using Dates: DateTime, TimeType
  using Dates
  using UUIDs: uuid4
  using NamedArrays: NamedArray
  using Ids: AssetId, FieldId, OrderId
  using AbstractFields: AbstractFieldOperation
  using Events: EventQueue, AbstractEvent, NewBarEvent, FieldCompletedProcessingEvent, OrderFillEvent, AbstractOrderEvent, OrderAckEvent
  using Events
  using Orders
  using Engine: CalcLattice, addfields!, newbar!
  using DataReaders: AbstractDataReader, fastforward!, popfirst!, peek

  ## Type definitions ##
  abstract type AbstractVerbosity end
  abstract type INFO <: AbstractVerbosity end
  abstract type DEBUG <: INFO end
  abstract type WARNING <: DEBUG end
  abstract type NOVERBOSITY <: WARNING end

  struct StrategyOptions
    datareaders::Dict{AssetId, DR} where {DR<:AbstractDataReader}
    fieldoperations::Vector{FO} where {FO<:AbstractFieldOperation}
    numlookbackbars::Integer
    start::ST where {ST<:Dates.TimeType}
    endtime::ET where {ET<:Dates.TimeType}
    barsize::BT where {BT<:Dates.Period}
    verbosity::DataType
    datadelay::DDT where {DDT<:Dates.Period}
    orderackdelay::ODT where {ODT<:Dates.Period}
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
                          datareaders::Dict{AssetId, DR},
                          fieldoperations::Vector{FO},
                          start::ST,
                          endtime::ET,
                          numlookbackbars::Integer=-1,
                          barsize::BT=Day(1),
                          verbosity::Type=NOVERBOSITY,
                          datadelay::DDT=1,
                          orderackdelay::ODT=1,
                          datetimecol::String="datetime",
                          opencol::String="open",
                          highcol::String="high",
                          lowcol::String="low",
                          closecol::String="close",
                          volumecol::String="volume",
                          ondataevent::Function=(dataevent->nothing),
                          onorderevent::Function=(orderevent->nothing),
                          principal::PT=100_000
                          ) where { DR<:AbstractDataReader, FO<:AbstractFieldOperation,
                          ST<:Dates.TimeType, ET<:Dates.TimeType, BT<:Dates.TimePeriod,
                          DDT<:Dates.Period, ODT<:Dates.Period, PT<:Number }
    return StrategyOptions(datareaders, fieldoperations, numlookbackbars,
      start, endtime, barsize, verbosity, datadelay, orderackdelay, datetimecol,
      opencol, highcol, lowcol, closecol, volumecol,  ondataevent, onorderevent,
      principal
    )
  end

  mutable struct Portfolio
    equity::Dict{AssetId, EN} where {EN<:Number} # amount of equity in each asset
    cash::CN where {CN<:Number}
    value::VN where {VN<:Number} # total value of the portfolio
    Portfolio(cash::N) where {N<:Number} = new(Dict{AssetId, Number}(), cash, cash)
  end

  mutable struct Strategy
    options::StrategyOptions
    events::EventQueue
    orders::Dict{OrderId, Orders.AbstractOrder}
    openorderids::Vector{OrderId}
    assetids::Vector{AssetId}
    portfolio::Portfolio
    lattice::CalcLattice
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
    addfields!(lattice, options.fieldoperations)
    return Strategy(
      options,
      EventQueue(),
      Dict{OrderId, Orders.AbstractOrder}(),
      Vector{OrderId}(),
      assetids,
      Portfolio(options.principal),
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

  curbarstarttime(strat::Strategy) = strat.options.start + (strat.curbarindex - 0) * strat.options.barsize

  nextbarstarttime(strat::Strategy) = curbarstarttime(strat) + strat.options.barsize

  ## Data access functions ##

  # vector of (assetid, fieldid)-value pairs. The entries in the vector are  in
  # chronological order, meaning that the last entry will represent the most recent bar.
  function getalldata(strat::Strategy)::Vector{NamedArray}
    map((barlayer -> barlayer.bardata), strat.lattice.recentbars)
  end

  # (assetid, fieldid)->value pairs for `ago` bars ago; if ago=0, then this
  # is equivalent to previousbardata(strat)
  function data(strat::Strategy, ago::Integer)::NamedArray
    """Gets data `ago` bars ago; if `ago=0`, this gets the current bar's data."""
    alldata = getalldata(strat)
    return alldata[length(alldata)-ago]
  end

  # (assetid)->value pairs for `ago` bars ago for a particular field; if ago=0, then
  # this is equivalent to previousbardata(strat, fieldid)
  data(strat::Strategy, ago::Integer, fieldid::FieldId)::NamedArray = data(strat, ago)[:, fieldid]

  # value for a particular field for a particular asset on a particular bar; if
  # ago=0, then this is equivalent to previousbardata(strat, assetid, fieldid)
  data(strat::Strategy, ago::Integer, assetid::AssetId, fieldid::FieldId) = data(strat, ago)[assetid, fieldid]

  # (assetid, fieldid)->value pairs for the previous bar.
  # For example, if the barsize is 1 minute, and the current time
  # is 11:33:25 (HH:MM:SS), then this would give data from
  # 11:32:00-11:32:59.999... . WE CANNOT ACCESS DATA FOR THE CURRENT BAR,
  # SINCE IT IS NOT COMPLETED YET (e.g. cannot access this bar's open price).
  previousbardata(strat::Strategy)::NamedArray = data(strat, 0)

  previousbardata(strat::Strategy, fieldid::FieldId)::NamedArray = data(strat, 0, fieldid)

  previousbardata(strat::Strategy, assetid::AssetId, fieldid::FieldId) = data(strat, 0, assetid, fieldid)

  ## Methods related to orders ##
  function order!(strat::Strategy, order::OT)::OrderId where {OT<:Orders.AbstractOrder}
    """Place an order that gets seen by the brokerage after `seen` amount of time."""
    # Generate an order id; include loop for robustness
    orderid = string(uuid4())
    while orderid in keys(strat.orders)
      orderid = string(uuid4())
    end
    # Store the order
    strat.orders[orderid] = order

    # See if the order would be filled during this bar.
    # If not, then store it as an open order.
    fillsthisbar = tryfillorder!(strat, order)
    if !fillsthisbar
      push!(strat.openorderids, orderid)
    end

    # Push order ack event
    Events.push!(
      strat.events,
      OrderAckEvent(
        strat.curtime + 2*strat.options.orderackdelay,
        orderid
    ))
    return orderid
  end

  function tryfillorder!(strat::Strategy, order::OT)::Bool where {OT<:Orders.AbstractOrder}
    """ASSUMES THAT WE ARE TRYING TO FILL THE ORDER AT THE BEGINNING OF A BAR!"""

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
      if strat.portfolio.cash + deltacash < 0
        throw(string("Tried to place order ", order, " at price ", mid, " but there is only ", strat.portfolio.cash, " of cash."))
      end
      Events.push!(strat.events, OrderFillEvent(
        strat.curtime + strat.options.orderackdelay, # fills as soon as it gets to the exchange
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

      # TODO: Figure out a better way of modelling when a limit order fills (maybe mid-bar?)
      # Right now we just assume that it fills as soon as we check (+ orderackdelay)
      if limitbuyfills || limitsellfills
        deltacash = -order.size*executionprice
        if strat.portfolio.cash + deltacash < 0
          throw(string("Tried to place order ", order, " at price ", mid, " but there is only ", strat.portfolio.cash, " of cash."))
        end
        Events.push!(strat.events, OrderFillEvent(
          strat.curtime + strat.options.orderackdelay,
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
      strat.portfolio.cash += event.deltacash

      # Update the value of the portfolio
      assetprices = previousbardata(strat, strat.options.closecol) # get the most recent value for the close of the bar; this isn't a perfect estimator of current value, since there's some lag
      equityvalue = 0
      for assetid in keys(strat.portfolio.equity)
        equityvalue += strat.portfolio.equity[assetid] * assetprices[assetid]
      end
      strat.portfolio.value = strat.portfolio.cash + equityvalue
    end
  end

  ## Methods related to event handling ##
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
    """Delegate particular events to their relevant event handlers."""
    strat.curtime = event.time

    if isa(event, NewBarEvent)
      onnewbarevent!(strat, event)
    elseif isa(event, FieldCompletedProcessingEvent)
      strat.options.ondataevent!(strat, event)
    elseif isa(event, AbstractOrderEvent)
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
    strat.curtime = curbarstarttime(strat)

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

    while !Events.empty(strat.events) && Events.peek(strat.events).time < nextbarstarttime(strat)
      event = Events.pop!(strat.events)
      log(strat, string("Processing `", typeof(event), "` event."), INFO)
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
    genesisfielddata = Dict{AssetId, Dict{FieldId, Any}}()
    for assetid in strat.assetids
      genesisfielddata[assetid] = popfirst!(strat.options.datareaders[assetid])
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

    for ago in 0:-1:0
      println(data(strat, ago))
    end

    log(strat, string("Completed running backtest after ", strat.curbarindex, " bars."), INFO)
  end
end
