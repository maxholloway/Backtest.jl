# TODO: Issues in the current project implementation that require resolution.

## Next Step
The current block is somewhat complicated. I want to test the entire pipeline. But I don't really want to write tests right now, since it's so far from complete (I know; this is a sin). And I don't want to implement a mechanism for accessing the currently available data until I know what data structure will underly the CalcLattice (whether that be a list of barlayers or a `pd.DataFrame`). But in order to decide on that data structure, I really need to know how parallel processing will be introduced into the program (see medium priority `engine` item below on || processing). So what do I do next? There are a couple options.
1. Write unit tests on the available parts of `engine`, `backtest`, and `datareader`. This is usually a good idea if there's an easy interface, but these are pretty co-dependent. Unit tests for `datareader` will be easy. Unit tests for `backtest` and `engine` don't quite make sense yet though, because I really should be testing for cracks in the || processing infrastructure. Sure, I can test the interface, but I might as well just wait until the tests I write are more applicable. So for now I'm going to hold off on writing tests.
    
2. Make a quick (30 minutes to 1 hour tops) patch that allows us to easily get data from CalcLattice in an ordered fashion, then continue developing the backtest engine. This isn't a horrible idea, but it's kind of like half-assing the first part. This is a really solid stopping point on the project, and it's probably best to improve what I already have before moving forward and forgetting its implementation. This isn't the best way for now.
    
3. Do a deep dive into how we could implement || processing in the `engine` DAG. And keep it simple! This isn't the best, because I want to port into Cython eventually.
    
4. Port into Cython!! This is it. The solution. I love it! Let's do it! Cython!!!!

## High priority
### Overall items
* Consider moving files / classes around.
    1. Perhaps move all exceptions into a single file. [tiny time commitment]
    2. Perhaps create an ID file that contains FieldId and AssetId. This could help avoid an appearance of circular dependencies (e.g. `engine.engine` contains `FieldId` that classes such as `fields.fields` uses, however `fields.fields` doesn't really depend on the major component of `engine.engine` (namely the `CalcLattice`); since `engine.engine` depends heavily on `fields.fields`, it looks like there's a circular dependency; this hurts package dependency readability). [tiny time commitment]
* Testing. Unit tests need to be written for all of the major functions. [large time commitment]
* Improve developer experience.
    * We can assume more information.
        * User should not have to specify the name of their columns if they just want OHLCV. They should only have to specify the column with the date IF that column is not the 0th column. Also, they should not have to specify columns that are OHLCV (our program should ignore capitalization).
            * Overall, it may just be nice to do it the same way that backtrader does it.
    * We can pretty-up the interface for making a field. Right now it's downright archaic (having the user provide a dict of attributes). The reason
    it is implemented this way is because we don't know what fields need to be passed. In the meantime, we can allow common terms to be passed as `kwargs`, such as `dependent_field_id`, `field_id`, and even `window_len`. However this is not optimal, since users may be confused why they can provide a `window_len` argument to non-window operations (such as cross-sectional operations or genesis operations).
    * Consider implementing a pipe operator for making fields. For example, let there be `close: Field`, then we could define an operator that transforms close and creates a new field. For example, it may look something like `close | SMA_Transform(new_field_id='SMA_close_15', window_len=15)`. Here, notice that `SMA_Transform` is NOT the same as `SMA`, since `SMA` is a `FieldOp` type that requires a lattice to initialize it. Instead, `SMA_Transform` is a wrapper that takes in a field and spits out another field. This is actually super interesting for a number of reasons. 
        1. First of all, this _could_ eliminate the need to have `field_id` attributes for our derived field initializations. For example, we know the name of the dependent field, and we know the operation, and all of its inputs, so we may be able to form a smart name (e.g. `SMA_close_15` could be generated automatically).
        2. Second, this would be a much cleaner interface for making transforms. It exploits the binary nature of field initialization (`independent -> dependent`), it gets rid of the need for the user to provide `dependent_field_id` everytime, it's pretty clear when used by people who have used `apache beam` (a small perk, but nevertheless a perk), and it doesn't require a weird archaice dictionary initialization schema.
    

### `strategy` items
* Implement an O(log(N)) time complexity insertion into the event queue (`strategy.stratety`). Right now it simply sorts the entire list, which takes at least O(N) time. [small time commitment]

## Medium priority

### Overall items
* Update docstrings in `engine.engine` and `strategy.strategy`. Particularly public methods.
* Identify sources of latency. It will be best to do this after tests are written. [large time commitment]

### `engine` items
* Implement `__check_DAG` in `engine.engine`.
* Strongly consider rewriting `BarLayer` to be a `pd.DataFrame`. This will include giving solid answers to the following:
    * What will happen if we decide to add parallel processing? Will the df be thread safe?
    * It would be really nice to provide a `pd.DataFrame` interface as some sort of `data` attribute in the backtest base class. Currently this could be the case, but it would require a call to the `CalcLattice.__pd_repr` method the get the pandas representation of the past bars. This could be a serious issue, since the runtime for that method is `O((number of assets)*(number of bars stored))`. Not great for a method that's called once on each bar of the backtest!
    * It will be best to tackle this after a definitive plan for parallel processing is complete. Until then, we can just make the calls to `__pd_repr`.

## Low priority
* Implement more operations.