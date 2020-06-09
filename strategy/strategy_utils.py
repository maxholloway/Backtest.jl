class FieldComputationLatencyException(Exception):
    def __init__(self, computation_start_time, computation_end_time, allotted_computation_time):
        super().__init__(f'Took too long to compute this bar\'s fields. Computation began at {computation_start_time}, and ended at {computation_end_time}, '+
            f'taking a total amount of time of {computation_end_time-computation_start_time}. However, the allotted computation time is {allotted_computation_time}.'
        )