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
export [check_cast] from "casts";
export [canonical_type] from "common";
export [error_at] from "common";
export [verify_injected] from "injected";
export [returns_fresh, takes_over] from "confinement";
export [LAZY_ATTRIBUTE, READS_ATTRIBUTE] from "lazy";
export [called_without_naming] from "lazy_methods";
export [COLD_ATTRIBUTE] from "platform";
export [is_enum, is_trait, method_of] from "enums";
export [HASH_METHOD] from "equatable";
export [check_runtime_hash_keys] from "hash_keys";
export [Export, Exports, Handle, STRING_FREE, is_export_string] from "export_table";
export [c_type, declarator, header, header_declarations] from "exports";
export [defaulted_params, fill_defaults] from "function_types_check";
export [display_name, set_name] from "names";
export [CALL_METHOD, CLOSURE_PREFIX, is_closure_struct] from "closures";
export [is_comparison, is_overflow_test, op_name, simd_result, weak_result] from "operators";
export [thread_local_constant] from "shared_type_checks";
export [Fingerprint] from "fingerprint";
export [begin_type_ids, end_type_ids] from "type_ids";
## Checked units and their records in the build cache.
export [
    CheckedUnit, drop_body, finish_checked, full_body, function_facts, interface_hash, resume_checked, settle_merged
] from "checked";
export [anchors_of, DeltaBase, function_name, MergeAnchors, RecordIn, RecordOut, summary_without_place] from "record";
export [index_module, index_resumed, interface_fields, read_module, write_module] from "record_codec";
export [method_key, PassState, PassTimes, pass_name] from "state";
export [StaticExpansion, StaticRecording, substitute_names] from "static_source";
export [attribute_arguments, attribute_name] from "attributes";
export [expression_loc] from "common";
export [STATIC_REFCOUNT] from "synthesize";
export [method_is_static] from "value_types";
## What the language server asks of a checked model.
export [field_type, local_type, member_at, member_loc, FoundMember] from "member_lookup";
export [other_names, OtherName] from "named_arguments";
