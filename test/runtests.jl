using Backtest
using Test
using NamedArrays
using Statistics
using DataFrames
using Dates
using CSV

@testset "Backtest.jl" begin

    # Tests the AbstractFields module
    @testset "AbstractFields" begin
        # Test that exceptions are thrown when calling dofieldop on abstract types
        struct  UndefWindowFieldOp <: Backtest.AbstractFields.AbstractWindowFieldOperation end
        windowfieldop = UndefWindowFieldOp()

        struct UndefCSFieldOp <: Backtest.AbstractFields.AbstractCrossSectionalFieldOperation end
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
        means = (x -> sum(x)/length(x)).(csdata)
        stddevs = Statistics.std.(csdata)
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

    # Tests the DataReaders module
    @testset "DataReaders" begin

        # Generate some data that spans 10 files with 1000 entries each
        nfiles = 10
        barsperfile = 1440
        drift = 1.001

        basedate = Dates.DateTime(1)
        dates = [basedate + Dates.Day(i) for i = 1:nfiles]
        datadir = "____tempdata___"
        mkdir(datadir)
        try
            filenames = ["$datadir/$(Dates.Date(date)).csv" for date in dates]

            (openbase, highbase, lowbase, closebase, volumebase) = (100, 120, 79.3, 98.1, 10000)
            oval = ((i, j) -> i+j)
            hval = ((i, j) -> i+j+10)
            lval = ((i, j) -> i+j-20)
            cval = ((i, j) -> i+j)
            vval = ((i, j) -> 100)
            for (i, filename) in enumerate(filenames)
                df = DataFrame(
                        DateTime = [dates[i] + Dates.Minute(j-1) for j in 1:barsperfile],
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
                @test_throws Backtest.Exceptions.DateTooEarlyError Backtest.DataReaders.fastforward!(datareader, Dates.DateTime(0))
                @test_throws Backtest.Exceptions.DateTooEarlyError Backtest.DataReaders.fastforward!(datareader, Dates.Date(0, 1, 1))

                # Test that fastforward makes the underlying DataReader's current time
                # be greater than the input time.
                @test Backtest.DataReaders.peek(datareader)["DateTime"] > basedate

                # Test that peek gives the expected result
                @test runthroughalldatareaders(datareader)

            end

            for datareader in makedatareaders()
                # Test that that fastforward throws an exception when the given date is too late
                @test_throws Backtest.Exceptions.DateTooFarOutError Backtest.DataReaders.fastforward!(datareader, Dates.DateTime(2030))

            end


        finally
            rm(datadir, recursive=true) # clean up
        end
    end

    # Tests the Engine module
    @testset "Engine" begin
        # 1. Make a bunch of data
        # 2. Create a CalcLattice, and
        # 3. For each bar of the data
        #     4. Calculate the actual field operation values
        #     5. Run the bar through CalcLattice, and get the result
        #     6. Test that expected result = received result
        #    end
    end

    # Tests the Events module
    @testset "Events" begin
        # Test the event queue:
        # 1. Make a sequenced list of DateTime, `sorted`
        # 2. Copy and scramble `sorted` to get a new list, `unsorted`
        # 3. Make a new event queue, and assert that it is empty
        # 4. One-by-one, push! the elements of `unsorted` into the event queue, and test that empty() is not true
        # 5. One-by-one, remove elements from the event queue (checking that peek == pop), and assert that they are in the right order (using `sorted` to check)
        # 6. Assert that the event queue is empty
        # 7. Do 1-6 again for Dates (instead of DateTime)
    end

    # Tests the Backtest.jl API
    @testset "API" begin

    end



end
# Backtest.Test.backtesttest()
