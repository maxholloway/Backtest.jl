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

