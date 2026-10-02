//! The driver's integration tests, one module per feature, linked into a
//! single test binary.
//!
//! One binary rather than one per file: each binary statically links LLVM
//! (tens of MB), so every extra one costs a link on every platform, and on
//! macOS Gatekeeper scans each freshly linked executable on its first run
//! (about 2s apiece on the CI runner). One binary also lets the harness run
//! tests from every module in parallel instead of binary after binary.
//!
//! Run one module with a filter: `cargo test --test integration io_tests::`.

mod archive_tests;
mod compress_tests;
mod support;

mod arithmetic_c_semantics_tests;
mod array_tests;
mod async_tests;
mod atomic_tests;
mod audit_fixes_tests;
mod build_cache_tests;
mod c_callback_tests;
mod cli_tests;
mod character_literal_tests;
mod closure_tests;
mod collection_literal_tests;
mod compile_tests;
mod copy_tests;
mod corpus_tests;
mod debug_info_tests;
mod determinism_tests;
mod diagnostic_tests;
mod digest_tests;
mod docs_examples_tests;
mod edge_case_tests;
mod enum_tests;
mod pattern_tests;
mod extern_string_arg_tests;
mod function_reference_tests;
mod function_value_tests;
mod generic_method_tests;
mod hash_tests;
mod http_tests;
mod implicit_conversion_tests;
mod interpolation_tests;
mod intrinsic_tests;
mod int16_tests;
mod io_tests;
mod json_tests;
mod ir_facts_tests;
mod iterator_tests;
mod link_tests;
mod loop_scope_tests;
mod map_tests;
mod lto_tests;
mod method_inference_tests;
mod module_tests;
mod named_argument_tests;
mod multidim_index_tests;
mod operator_tests;
mod overflow_tests;
mod panic_location_tests;
mod overload_tests;
mod nested_array_tests;
mod nested_hash_tests;
mod optional_tests;
mod param_default_tests;
mod pep_fmt_tests;
mod pepper_entry_tests;
mod platform_tests;
mod os_tests;
mod process_tests;
mod propagation_tests;
mod property_tests;
mod ptr_syntax_tests;
mod refcount_optimizer_tests;
mod reflection_tests;
mod regex_tests;
mod result_tests;
mod runtime_docs_tests;
mod shared_ptr_semantics_tests;
mod socket_tests;
mod task_tests;
mod tls_tests;
mod static_call_tests;
mod store_type_tests;
mod string_tests;
mod temp_lifetime_tests;
mod trait_value_tests;
mod tuple_tests;
mod unary_operator_tests;
mod uri_tests;
mod value_struct_tests;
mod variadic_extern_tests;
mod visibility_tests;
mod weak_tests;
mod with_tests;
