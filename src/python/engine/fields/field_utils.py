from typing import Set

# Parameters that a user should not provide when defining lattice.
PROHIBITED_USER_PROVIDED_FIELD_ATTRIBUTES = {'lattice',}
FIELD_OPERATION_KW, FIELD_ID_KW, DEP_FIELD_ID_KW = 'field_operation', 'field_id', 'dependent_field_id'

def get_field_op_user_args(field_op) -> Set[str]:
    """Get all of the user-relevatnt arguments for to initializing 
    this FieldOp. Do not include 'self' and 'lattice', since user does
    not use those arguments (they are given inside engine.engine.CalcLattice).

    Args:
        field_op (Type[FieldOp]): Class that derives from FieldOp.

    Returns:
        Set[str]: Arguments to __init__ of the FieldOp.
    """
    all_args = field_op.__init__.__code__.co_varnames
    unnecessary_user_args = {'self'}.union(PROHIBITED_USER_PROVIDED_FIELD_ATTRIBUTES)
    is_necessary = lambda x: (x not in unnecessary_user_args)
    return set(filter(is_necessary, all_args))

def get_field_op_user_optional_args(field_op) -> Set[str]:
    """Get all of the optional arguments for initializing this FieldOp.

    Args:
        field_op (Type[FieldOp]): Class that derives from FieldOp.

    Returns:
        Set[str]: Default arguments to __init__ of the FieldOp.
    """
    default_args = field_op.__init__.__defaults__
    if default_args:
        n_default_args = len(default_args)
        return set(field_op.__init__.__code__.co_varnames[-n_default_args:]) # all default args are at the end
    else:
        return set() # no default args, so return all args
   
def get_field_op_user_required_args(field_op) -> Set[str]:
    """Get all of the required arguments for initializing this FieldOp.

    Args:
        field_op (Type[FieldOp]): Class that derives from FieldOp.

    Returns:
        Set[str]: Required arguments to __init__ of the FieldOp.
    """
    required_args = get_field_op_user_args(field_op) - get_field_op_user_optional_args(field_op)
    return required_args

