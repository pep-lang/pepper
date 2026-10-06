## The compiler's semantic analysis: the model the builder makes of a linked
## program (`model.pep`), and the passes that check and rewrite it.
export * from "loc";
export * from "model";
export * from "type_name";
export * from "walk";
export * from "builder";
export * from "program";
export * from "passes";
## What the code generator uses from the passes.
export [
    conditional_result, is_float_type, is_numeric_type, is_unsigned_int_type, result_type, stored_as
] from "arithmetic";
export [cast_spelled, check_cast] from "casts";
export [error_at] from "common";
export [returns_fresh, takes_over] from "confinement";
export [LAZY_ATTRIBUTE, READS_ATTRIBUTE] from "lazy";
export [is_enum, is_trait, method_of] from "enums";
export [HASH_METHOD] from "equatable";
export [STRING_FREE, is_export_string] from "exports";
export [defaulted_params, fill_defaults] from "function_types_check";
export [set_name] from "names";
export [is_comparison, is_overflow_test, op_name, simd_result, weak_result] from "operators";
export [thread_local_constant] from "shared_type_checks";
export [Fingerprint] from "fingerprint";
## Checked units and their records in the build cache.
export [CheckedUnit, finish_checked, resume_checked] from "checked";
export [RecordIn, RecordOut] from "record";
export [read_module, write_module] from "record_codec";
export [PassState] from "state";
export [attribute_arguments, attribute_name, expression_loc] from "static_blocks";
export [STATIC_REFCOUNT] from "synthesize";
export [method_is_static] from "value_types";
## What the language server asks of a checked model.
export [field_type, local_type, member_at, member_loc, FoundMember] from "member_lookup";
export [other_names, OtherName] from "named_arguments";
