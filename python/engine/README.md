# Engine

## Interface Overview
    Engine allows for event driven calculations. The fundamental data structure
    behind Engine is the CalcLattice. In the same way that a lattice is a 3-dimensional structure composed of nodes and edges, we say that a CalcLattice is a structured 3-dimensional collection on values. The dimensions (in no particular order) are (`Asset`, `Field`, `Bar`). Any value in the CalcLattice can be defined by these three identifiers.

    CalcLattice has the following basic interface:
        1. Instantiate the CalcLattice, determining up-front what assets will be stored in it and how many bars into the past will be kept. This should be the maximum number of bars back to look, no more and no less. Note: There is currently no option for declaring fields at instantiation time.
        2. Add fields to the CalcLattice (note: this must be done before adding data to the lattice). There are three major types of fields:
            1. Genesis Fields: fields that are given a priori, such as OHLCV data.
            2. Window Fields: fields that use a window operation to create each entry. An example of this would be a 30 bar moving average. All window fields are of the patter (past n bars of data) -> value. In general, window operations are reductions on the past n bars into a single value; this value need not be numeric.
            3. Cross Sectional Fields: fields that calculate a metric across all of the assets on a particular bar. Perhaps in future versions there will be functionality to partition assets into different sectors or sub-sectors (e.g. tech, industrials, etc.). But for now, these functions are fairly simple. They take in data for all assets of a particular field on a particular bar, and they map each asset value to a new asset value. For example, a cross-sectional metric may be the z-score of returns across assets. In this example, our input data would be a mapping from assets to returns, we would calculate the z-score of each asset ```(asset_val - mean(data)) /  stddev(data)```. This is the standard format for a cross-sectional operation.
        3. Use it. The main way we use CalcLattice is by feeding in a bar of data in the format Dict[AssetId, Dict[FieldId, value]]. After adding in the bar of data, the CalcLattice will automatically calculate all downstream fields (e.g. feed in OHLCV data -> Returns (over 1 bar) -> 30 bar moving average of Returns -> StdDev of 30 bar moving average over returns). The pipeline for getting data back out is still in the works.

## Implementation Primer

    Can you say "DAG" (directed acyclic graph)?! Engine is primarily comprised of the CalcLattice. The CalcLattice is composed of BarLayers, and each BarLayer contains all of the (Asset, Field) data for a particular bar. The reason this is a DAG is because of there is a dependency tree among the different fields. If you look back at the interface overview, you see that both the window and cross sectional field types take one field as input, and the genesis fields effectively take 0 fields as input (they start the DAG, hence the name "genesis").

    So why does it matter that this is a DAG? Well, it matters a lot due to the way that the DAG is processed. When a new bar of (AssetId, genesis field id) data is added by the `add_bar` method, the DAG automatically executes a depth-first. Since each field has at most one dependent field, and the DAG is connected, we can guarantee that if field C depends on field B depends on field A (A->B->C), then once A's value is known, we need no other values in order to compute B (since B can depend on at most 1 other field). Thus, computing all of the fields is equivalent to traversing the field DAG.

    The constraint that all fields depend on at most a single field seems strict; however, we find that (a) this pattern is very common in finance algos, and (b) any more complicated operations (such as a binary operation between two fields) can be performed in a `backtest` instance.

    There are two main reasons why Engine uses these constraints. The primary reason is for developer experience / maintainability. Creating a general graph-flow Engine is interesting, but may ignore the helpful constraints of the problem (e.g. bar data is sequential, all fields are computed for all assets). Plus, it'd be a headache to maintain, since such an implementation would be rather cryptic. The second reason that we used these constraints is that they allow for a very high level of parallelism. Since any non-genesis field B depends on only one other field A, we can begin computing B as soon as A completes, without waiting for another process to complete. Visually, this means that there is no interleaving among branches of the DAG (note: this constraint is even stronger than the fundamental DAG constraint). Therefore, we can seamlessly use multithreading by allowing threads to perform depth-first traversals of the different branches.