if __name__ == "__main__":
    from engine.engine_utils import FieldId
    from fields.fields import Field, SMA

    open_id = FieldId('open')
    sma_id = FieldId('SMA-open-15')

    # Test: Correct example; GOOD
    sma_field_params = {
        'field_operation': SMA,
        'field_id': sma_id,
        'dependent_field_id': open_id,
        'window_len': 15
    }

    # # Test: Includes forbidden attribute; GOOD
    # sma_field_params = {
    #     'field_operation': SMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15,
    #     'lattice': 'hehe I included a lattice object'
    # }

    # # Test: Incorrect type on field_operation; GOOD
    # sma_field_params = {
    #     'field_operation': '',
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15
    # }

    # # Test: No field_operation; GOOD
    # sma_field_params = {
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15
    # }

    # # Test: Bad field_id type; GOOD
    # sma_field_params = {
    #     'field_operation': SMA,
    #     'field_id': '',
    #     'dependent_field_id': open_id,
    #     'window_len': 15
    # }

    # # Test: Bad dependent_field_id type; GOOD
    # sma_field_params = {
    #     'field_operation': SMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': '',
    #     'window_len': 15
    # }

    # # Test Missing required parameter; GOOD
    # sma_field_params = {
    #     'field_operation': SMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    # }


    # # Test: Ensure no errors occur when using no extra parameters; GOOD
    # class TestSMA(SMA):
    #     def __init__(self, window_len, dependent_field_id, field_id, lattice, 
    #       other=None, other2=2, other3=3, other4=4, otherN=None):
    #         self.other=other
    # sma_field_params = {
    #     'field_operation': TestSMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15
    # }

    # # Test: Ensure no errors occur when using some extra parameters; GOOD
    # class TestSMA(SMA):
    #     def __init__(self, window_len, dependent_field_id, field_id, lattice, 
    #       other1=None, other2=2, other3=3, other4=4, otherN=None):
    #         self.other=other
    # sma_field_params = {
    #     'field_operation': TestSMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15, 
    #     'other1': 1,
    #     'other2': 2
    # }

    # # # Test: Ensure error occurs when specifying non-existent attribute; GOOD
    # class TestSMA(SMA):
    #     def __init__(self, window_len, dependent_field_id, field_id, lattice, 
    #       other1=None, other2=2, other3=3, other4=4, otherN=None):
    #         self.other=other
    # sma_field_params = {
    #     'field_operation': TestSMA,
    #     'field_id': sma_id,
    #     'dependent_field_id': open_id,
    #     'window_len': 15, 
    #     'other1': 1,
    #     'otherM': 2
    # }


    sma_field = Field(sma_field_params)