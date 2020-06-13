import datetime as dt
from strategy.strategy import Backtest, BacktestOptions, VerbosityLevel
from datareader.datareader import DataReader, DataReaderOptions
from ids.ids import FieldId
from engine.fields.fields import Field, SMA, InjectionOp


class EmptyBacktest(Backtest):

    def on_data_event(self, event):
        # print(self._Backtest__calclattice)
        return

    def on_order_event(self, event):
        return
    pass


if __name__ == "__main__":
    """Example that details how to create a backtest.
    """
    
    # * Create the backtest object
    backtest_options = BacktestOptions(
        barsize=dt.timedelta(minutes=1),
        open_delay_seconds=5,
        num_bars_to_store=100,
        verbosity=VerbosityLevel.NONE,
    )
    start = dt.datetime(year=2019, month=6, day=1)
    end = dt.datetime(year=2019, month=6, day=1, hour=1, minute=5)#hour=23, minute=59)
    
    backtest = EmptyBacktest(start=start, end=end, options=backtest_options)
    # print(bt.__dict__)

    # * Add data to the backtest
    TIME, OPEN, HIGH, LOW, CLOSE, VOLUME = FieldId('dtime'), FieldId('open'), FieldId('high'), FieldId('low'), FieldId('close'), FieldId('volume')
    field_name_to_field_id = {
        'Opened': TIME, 'Open': OPEN, 'High': HIGH, 
        'Low': LOW, 'Close': CLOSE, 'Volume': VOLUME}
    
    btc_path_base = 'data/crypto/BTCUSDT/individual_csvs/'
    btcusdt_dr = DataReader(
        asset_id = 'BTCUSDT',
        data_paths=[btc_path_base+'2019-06-01.csv', btc_path_base+'2019-06-02.csv'],
        reader_options=DataReaderOptions(
            read_csv_options={'index_col':'Opened', 'parse_dates': True, 'infer_datetime_format': True},
            field_name_to_field_id=field_name_to_field_id
            ))
    
    backtest.add_data(btcusdt_dr)    
    # print(f'BT Dict [should have an entry in `__asset_ids`]: {backtest.__dict__}')

    # * Add fields to the backtest
    for field_id in [OPEN, HIGH, LOW, CLOSE, VOLUME]:
        backtest.add_field(
            Field(
                {'field_id': field_id, 'field_operation': InjectionOp}
            )
        )
    open_mavg15 = Field({
            'field_id': FieldId('SMA-open-15'),
            'field_operation': SMA,
            'dependent_field_id': CLOSE,
            'window_len': 3
        })
    backtest.add_field(open_mavg15)

    # * Run the backtest
    backtest.run()

    print(backtest._Backtest__calclattice)

    pass