from engine.engine import AssetId

class NoMoreDataAvailableException(Exception):
    def __init__(self, asset_id: AssetId):
        super().__init__(f'Tried to access a bar that does not exist for asset={asset_id}.')