from typing import Any
from engine.engine import AssetId, FieldId

class Event:
    def __init__(self, time: dt.datetime):
        self.time = time
        return

class NewBarEvent(Event):
    def __init__(self, time: dt.datetime, genesis_data: Dict[AssetId, Dict[FieldId, Any]]):
        super().__init__(time)
        self.genesis_data = genesis_data
        pass
    
class FieldProcessingCompleteEvent(Event):
    def __init__(self, time: dt.datetime):
        super().__init__(time)

class OrderEvent(Event):
    def __init__(self, time: dt.datetime):
        super().__init__(time)
        