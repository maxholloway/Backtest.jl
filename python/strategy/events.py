from typing import Dict, Any
import datetime as dt
from engine.engine import AssetId, FieldId

class EventBase:
    def __init__(self, time: dt.datetime):
        self.time = time
        return

class NewBarEvent(EventBase):
    def __init__(self, time: dt.datetime, genesis_data: Dict[AssetId, Dict[FieldId, Any]]):
        super().__init__(time)
        self.genesis_data = genesis_data
        pass
    
class FieldProcessingCompletedEvent(EventBase):
    def __init__(self, time: dt.datetime):
        super().__init__(time)

class OrderEvent(EventBase):
    def __init__(self, time: dt.datetime):
        super().__init__(time)
        