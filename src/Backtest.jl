# module Ids
#   const AssetId = String
#   const FieldId = String
#   const OrderId = String
#
#   # Basic type definitions #
#   # abstract type Id end
#   #
#   # struct AssetId <: Id
#   #   id::String
#   # end
#   #
#   # struct FieldId <: Id
#   #   id::String
#   # end
#
#   # convert(::Type{FieldId}, id::String) = FieldId(id)
#   # convert(::Type{AssetId}, id::String) = Assetid(id)
#   # convert(::Type{String}, id::T) where {T<:Id} = id.id
#
# end # module


module Backtest
  using Dates: DateTime, TimeType
  using Dates
  using UUIDs: uuid4
  using NamedArrays: NamedArray
  using Ids: AssetId, FieldId, OrderId
  using AbstractFields: AbstractFieldOperation
  using ConcreteFields: Open, High, Low, Close, Volume
  using Events: EventQueue, AbstractEvent, NewBarEvent, FieldCompletedProcessingEvent, OrderFillEvent, AbstractOrderEvent, OrderAckEvent
  using Events
  using Orders
  using Engine: CalcLattice, addfields!, newbar!
  using DataReaders: AbstractDataReader, fastforward!, popfirst!, peek

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
    barsize::BT where {BT<:Dates.Period}
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
                          barsize::BT=Day(1),             # how much time there is between the start of two consecutive bars; TODO: how does this work for data with gaps?
                          verbosity::Type=NOVERBOSITY,    # how much verbosity the backtest should have; INFO gives the most messages, and NOVERBOSITY gives the fewest
                          datadelay::DDT=Dates.Millisecond(100), # how much time transpires at the beginning of a bar before data is received; e.g. if this is 5 seconds, then data will be `received` by the backtest 5 seconds after the bar starts.
                          messagelatency::ODT=Dates.Millisecond(100), # how much time it takes to transmit a message to a brokerage/exchange
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
                          ST<:Dates.TimeType, ET<:Dates.TimeType, BT<:Dates.TimePeriod,
                          DDT<:Dates.Period, ODT<:Dates.Period, PT<:Number }
    return StrategyOptions(datareaders, fieldoperations, numlookbackbars,
      start, endtime, barsize, verbosity, datadelay, messagelatency, datetimecol,
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
    For example, if the barsize is 1 minute, and the current time
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

  curbarstarttime(strat::Strategy) = strat.options.start + (strat.curbarindex - 0) * strat.options.barsize

  nextbarstarttime(strat::Strategy) = curbarstarttime(strat) + strat.options.barsize

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
    """
    NOTE: ASSUMES THAT WE ARE TRYING TO FILL THE ORDER AT THE BEGINNING OF A BAR!"""

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
        executiontime = randomtimeininterval(strat.curtime+strat.options.messagelatency, nextbarstarttime(strat)+strat.options.messagelatency)
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
    if timeaftercomputation > nextbarstarttime(strat)
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
    while nextbarexists(strat)
      genesisfielddata = loadgenesisdata!(strat)
      runnextbar!(strat, genesisfielddata)
    end

    # Finish the backtest
    onend(strat)
  end

  export run, data, numbarsavailable
end
