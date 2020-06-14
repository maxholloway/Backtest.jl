import datetime as dt
from strategy.strategy import Backtest, BacktestOptions, VerbosityLevel
from datareader.datareader import DataReader, DataReaderOptions
from engine.engine import FieldId
from engine.fields.fields import Field, SMA


class EmptyBacktest(Backtest):

    def on_data_event(self, event):
        print('Here!')
        print(self._Backtest__calclattice)
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
        verbosity=VerbosityLevel.HIGH,
    )
    start = dt.datetime(year=2019, month=6, day=1)
    end = dt.datetime(year=2019, month=6, day=1, hour=1, minute=0)#hour=23, minute=59)
    
    backtest = EmptyBacktest(start=start, end=end, options=backtest_options)
    # print(bt.__dict__)

    # * Add data to the backtest
    btcusdt_dr = DataReader(
        asset_id = 'BTCUSDT',
        data_paths=['data/crypto/BTCUSDT/individual_csvs/2019-06-01.csv'],
        reader_options=DataReaderOptions({'index_col':'Opened', 'parse_dates': True, 'infer_datetime_format': True})
    )
    backtest.add_data(btcusdt_dr)    

    # * Add fields to the backtest
    open_mavg15 = Field({
            'field_id': FieldId('SMA-Open-15'),
            'field_operation': SMA,
            'dependent_field_id': FieldId('Open'),
            'window_len': 15
        })
    backtest.add_field(open_mavg15)

    # * Run the backtest
    backtest.run()


    pass