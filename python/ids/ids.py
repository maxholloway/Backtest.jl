class AssetId:
    def __init__(self, asset_id):
        self._asset_id = asset_id

    def __eq__(self, other):
        return (self._asset_id == other._asset_id)

    def __hash__(self):
        return hash(self._asset_id)

    def __repr__(self):
        return 'AssetId({})'.format(self._asset_id)
    
    def __str__(self):
        return str(self._asset_id)


class FieldId:
    def __init__(self, field_id):
        self._field_id = field_id

    def __eq__(self, other):
        return (self._field_id == other._field_id)

    def __hash__(self):
        return hash(self._field_id)

    def __repr__(self):
        return 'FieldId({})'.format(self._field_id)
    
    def __str__(self):
        return str(self._field_id)
