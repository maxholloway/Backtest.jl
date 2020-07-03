import Backtest
import Test: @test, @testset, @test_throws
import NamedArrays: NamedArray
import Statistics: mean, std
import DataFrames: DataFrame
import Dates: Minute, Day, Date, DateTime
import CSV
import Random: MersenneTwister, randperm

# Type definitions (defined here to avoid local-type-definition error)
struct  UndefWindowFieldOp <: Backtest.AbstractFields.AbstractWindowFieldOperation end
struct UndefCSFieldOp <: Backtest.AbstractFields.AbstractCrossSectionalFieldOperation end


@testset "Backtest.jl" begin

    # Tests the AbstractFields module
    @testset "AbstractFields" begin
        # Test that exceptions are thrown when calling dofieldop on abstract types
        windowfieldop = UndefWindowFieldOp()
        crossectionalfieldop = UndefCSFieldOp()

        @test_throws Exception Backtest.AbstractFields.dofieldop(windowfieldop, [])
        @test_throws Exception Backtest.AbstractFields.dofieldop(crossectionalfieldop, Dict{String, Any}())
    end

    # Tests the ConcreteFields module
    @testset "ConcreteFields" begin
        # Test default constructor for OHLCV
        @test Backtest.ConcreteFields.Open() == Backtest.ConcreteFields.Open("Open")
        @test Backtest.ConcreteFields.High() == Backtest.ConcreteFields.High("High")
        @test Backtest.ConcreteFields.Low() == Backtest.ConcreteFields.Low("Low")
        @test Backtest.ConcreteFields.Close() == Backtest.ConcreteFields.Close("Close")
        @test Backtest.ConcreteFields.Volume() == Backtest.ConcreteFields.Volume("Volume")


        # Test default window field operation constructors
        @test Backtest.ConcreteFields.Returns("", "", 2) == Backtest.ConcreteFields.Returns("", "")
        @test Backtest.ConcreteFields.LogReturns("", "", 2) == Backtest.ConcreteFields.LogReturns("", "")


        function windows(vec, n)
            return [windowdata[i:i+n] for i = 1:length(vec)-n]
        end

        # Data to be used for window field operations
        windowdata = [i*1.0 for i = 1:15]
        n_to_windows = Dict{Integer, Vector}()
        n_to_windows[2]=windows(windowdata, 2)
        n_to_windows[3]=windows(windowdata, 3)
        n_to_windows[10]=windows(windowdata, 10)

        makeexpectedreturns(n) = (x -> (x[n]-x[1]) / x[1])
        expectedreturns = makeexpectedreturns(2)

        makeexpectedlogreturns(n) = (x -> log(x[n]/x[1]))
        expectedlogreturns = makeexpectedlogreturns(2)

        makeexpectedsma(n) = (x->sum(x)/length(x))

        for n in keys(n_to_windows)
            # make field operations
            returnsop = Backtest.ConcreteFields.Returns("", "", n)
            logreturnsop =Backtest.ConcreteFields.LogReturns("", "", n)
            smaop = Backtest.ConcreteFields.SMA("", "", n)

            # test dofieldop
            windows = n_to_windows[n]
            for window in windows
                @test Backtest.ConcreteFields.dofieldop(returnsop, window) == makeexpectedreturns(n)(window)
                @test Backtest.ConcreteFields.dofieldop(logreturnsop, window) == makeexpectedlogreturns(n)(window)
                @test Backtest.ConcreteFields.dofieldop(smaop, window) == makeexpectedsma(n)(window)
            end
        end

        # Create data to be used for cross sectional field operations
        names = ["A", "B", "C", "D"]
        csdata = [
            NamedArray([1.0, 2, 3, 4], (names,) ),
            NamedArray([3, 1, 40, -2], (names,))
        ]

        # Test Z-Score
        means = mean(csdata)
        means = (x -> sum(x)/length(x)).(csdata)
        stddevs = std.(csdata)
        function makezscorefn(mu, sigma)
            function zscorefn(x)
                return (x-mu)/sigma
            end
            return zscorefn
        end
        zscorefns = [makezscorefn(mean, stddev) for (mean, stddev) in zip(means, stddevs)]

        zsc = Backtest.ConcreteFields.ZScore("", "")
        for (i, csdatum) in enumerate(csdata)
            expectedresults = zscorefns[i].(csdatum)
            actualresults = Backtest.ConcreteFields.dofieldop(zsc, csdatum)
            @test expectedresults == actualresults
        end

        # Test rank
        expectedranks = [
            NamedArray([4, 3, 2, 1], (names,)),
            NamedArray([2, 3, 1, 4], (names,))
        ]
        makerankdofieldop() = (datum -> Backtest.ConcreteFields.dofieldop(Backtest.ConcreteFields.Rank("", ""), datum))
        actualranks = makerankdofieldop().(csdata)
        @test expectedranks == actualranks
    end

    # Tests the Engine module
    @testset "Engine" begin
        nbarsstoredoptions =
        assetids = ["A", "B", "C"]
        (O, H, L, C, V) = ("Open", "High", "Low", "Close", "Volume")
        function testengine(nbarstostore)
            lattice = Backtest.Engine.CalcLattice(nbarstostore, assetids)
            @test Backtest.Engine.numbarsavailable(lattice) == 0
            @test_throws Exception Backtest.Engine.data(lattice)

            # Make field operations and add them to the backtest
            fieldoperations = [
                Backtest.ConcreteFields.Open(O),
                Backtest.ConcreteFields.High(H),
                Backtest.ConcreteFields.Low(L),
                Backtest.ConcreteFields.Close(C),
                Backtest.ConcreteFields.Volume(V),
                Backtest.ConcreteFields.SMA("SMA1High", H, 1),
                Backtest.ConcreteFields.SMA("SMA2Open", O, 2),
                Backtest.ConcreteFields.Rank("RankLow", L),
                Backtest.ConcreteFields.Rank("RankSMA1High", "SMA1High")
            ]
            Backtest.Engine.addfields!(lattice, fieldoperations)

            # Make bars of data and run them
            allbars = [
                Dict(
                    "A" => Dict(O=>10, H=>15, L=>8, C=>11, V=>10000),
                    "B" => Dict(O=>100, H=>101, L=>90, C=>93, V=>101),
                    "C" => Dict(O=>60, H=>80, L=>60, C=>80, V=>10000),
                ),
                Dict(
                    "A" => Dict(O=>11, H=>11, L=>3, C=>6, V=>8000),
                    "B" => Dict(O=>93, H=>100, L=>90, C=>99, V=>101),
                    "C" => Dict(O=>80, H=>80, L=>60, C=>80, V=>10000),
                )
            ]

            # Test that the first bar of data gets loaded properly and
            # computes dependent fields
            Backtest.Engine.newbar!(lattice, allbars[1])
            @test Backtest.Engine.data(lattice, "A", O) == 10
            @test Backtest.Engine.data(lattice, "B", "SMA1High") == 101
            @test Backtest.Engine.data(lattice, "B", "RankLow") == 1
            @test Backtest.Engine.data(lattice, "C", "RankLow") == 2
            @test Backtest.Engine.data(lattice, "B", "RankSMA1High") == 1

            @test Backtest.Engine.numbarsavailable(lattice) == 1

            # Test that the second bar of data gets load
            Backtest.Engine.newbar!(lattice, allbars[2])
            Backtest.Engine.data(lattice, "A", O)
            @test Backtest.Engine.data(lattice, "A", O) == 11
            @test Backtest.Engine.data(lattice, "B", "SMA1High") == 100
            @test Backtest.Engine.data(lattice, "B", "RankLow") == 1
            @test Backtest.Engine.data(lattice, "C", "RankLow") == 2
            @test Backtest.Engine.data(lattice, "B", "RankSMA1High") == 1
            @test Backtest.Engine.data(lattice, "A", "SMA2Open") == (10+11)/2
            @test Backtest.Engine.data(lattice, "B", "SMA2Open") == (93+100)/2
            @test Backtest.Engine.data(lattice, "C", "SMA2Open") == (60+80)/2


            @test Backtest.Engine.numbarsavailable(lattice) == 2
        end

        testengine(-1)
        testengine(5)
        testengine(1_000_000_000)
    end

    # Tests the DataReaders module
    @testset "DataReaders" begin
        # Generate some data that spans 10 files with 1000 entries each
        nfiles = 10
        barsperfile = 5

        basedate = DateTime(1)
        dates = [basedate + Day(i) for i = 1:nfiles]
        datadir = "____tempdata___"
        mkdir(datadir)
        try
            filenames = ["$datadir/$(Date(date)).csv" for date in dates]

            (openbase, highbase, lowbase, closebase, volumebase) = (100, 120, 79.3, 98.1, 10000)
            oval = ((i, j) -> i+j)
            hval = ((i, j) -> i+j+10)
            lval = ((i, j) -> i+j-20)
            cval = ((i, j) -> i+j)
            vval = ((i, j) -> 100)
            for (i, filename) in enumerate(filenames)
                df = DataFrame(
                        DateTime = [dates[i] + Minute(j-1) for j in 1:barsperfile],
                        Open = [oval(i, j) for j in 1:barsperfile],
                        High = [hval(i, j) for j in 1:barsperfile],
                        Low = [lval(i, j) for j in 1:barsperfile],
                        Close = [cval(i, j) for j in 1:barsperfile],
                        Volume = [vval(i, j) for j in 1:barsperfile]
                    )
                CSV.write(filename, df)
            end

            function makedatareaders()
                # Make all of the datareaders
                return [
                    Backtest.DataReaders.InMemoryDataReader(
                        "",
                        filenames,
                        datetimecol="DateTime",
                        dtfmt="yyyy-mm-ddTHH:MM:SS")
                ]
            end

            # end

            function runthroughalldatareaders(datareader)
                for i in 1:nfiles
                    for j in 1:barsperfile
                        peekval =  Backtest.DataReaders.peek(datareader)
                        popval =  Backtest.DataReaders.popfirst!(datareader)
                        @assert peekval == popval
                        @assert peekval["Open"] == oval(i, j)
                        @assert peekval["High"] == hval(i, j)
                        @assert peekval["Low"] == lval(i, j)
                        @assert peekval["Close"] == cval(i, j)
                        @assert peekval["Volume"] == vval(i, j)
                    end
                end
                return true
            end

            for datareader in makedatareaders()
                # Test that that fastforward throws an exception when the given date is too early
                @test_throws Backtest.Exceptions.DateTooEarlyError Backtest.DataReaders.fastforward!(datareader, DateTime(0))
                @test_throws Backtest.Exceptions.DateTooEarlyError Backtest.DataReaders.fastforward!(datareader, Date(0, 1, 1))

                # Test that fastforward makes the underlying DataReader's current time
                # be greater than the input time.
                @test Backtest.DataReaders.peek(datareader)["DateTime"] > basedate

                # Test that peek gives the expected result
                @test runthroughalldatareaders(datareader)

            end

            for datareader in makedatareaders()
                # Test that that fastforward throws an exception when the given date is too late
                @test_throws Backtest.Exceptions.DateTooFarOutError Backtest.DataReaders.fastforward!(datareader, DateTime(2030))

            end


        finally
            rm(datadir, recursive=true) # clean up
        end
    end

    # Tests the Events module
    @testset "Events" begin
        exampleorder = Backtest.Orders.MarketOrder("A", 10)
        sortedevents = [
            Backtest.Events.NewBarEvent(DateTime(0), Dict(""=>Dict(""=>nothing))),
            Backtest.Events.FieldCompletedProcessingEvent(DateTime(1)),
            Backtest.Events.OrderAckEvent(DateTime(1, 2), "__an_order_id"),
            Backtest.Events.OrderFillEvent(DateTime(1, 3), exampleorder, 100, -1),

            Backtest.Events.NewBarEvent(DateTime(2), Dict(""=>Dict(""=>nothing))),
            Backtest.Events.FieldCompletedProcessingEvent(DateTime(3)),
            Backtest.Events.OrderAckEvent(DateTime(3, 2), "__an_order_id"),
            Backtest.Events.OrderFillEvent(DateTime(3, 3), exampleorder, 100, -1),

            Backtest.Events.NewBarEvent(DateTime(4), Dict(""=>Dict(""=>nothing))),
            Backtest.Events.FieldCompletedProcessingEvent(DateTime(5)),
            Backtest.Events.OrderAckEvent(DateTime(5, 2), "__an_order_id"),
            Backtest.Events.OrderFillEvent(DateTime(5, 3), exampleorder, 100, -1)
        ]

        seed = MersenneTwister(1234)
        indexpermutations = randperm(seed, length(sortedevents))

        eventq = Backtest.Events.EventQueue()
        @test Backtest.Events.empty(eventq)

        for index in indexpermutations
            Backtest.Events.push!(eventq, sortedevents[index])
            @test !Backtest.Events.empty(eventq)
        end

        for event in sortedevents
            @test event == Backtest.Events.peek(eventq)
            @test event == Backtest.Events.pop!(eventq)
        end

        @test Backtest.Events.empty(eventq)
    end

    # Tests the Backtest.jl API
    @testset "API" begin
        # TODO: Write tests for the backtest API
    end

    @testset "Utils" begin

    end
end
