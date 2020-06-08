"""Helper functions for engine.
"""

# Exceptions
class StaticDAGException(Exception):
    def __init__(self):
        super().__init__('Cannot modify DAG after execution begins. Ensure program does not attempt to add a field after DAG execution has begun.')

class DAGStatusCodes:
    """Error codes for different problems with the field dependency DAG.
    """

    CIRCULAR: int = -1  # DAG has circular dependencies
    OK: int = 1         # there are problems with the DAG

class BadDAGException(Exception):
    def __init__(self, error_code: int):
        message = ''
        if error_code == DAGStatusCodes.CIRCULAR:
            message = 'DAG has circular dependencies. Ensure that no fields depend on one another.'
        else:
            raise ValueError('Unknown `error_code` for DAG Exception.')
        super().__init__(message)



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
