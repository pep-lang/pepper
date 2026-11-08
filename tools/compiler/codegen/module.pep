## Code generation: the checked model to LLVM IR, through the pepper-llvm
## package.

export * from "generator";
export * from "partition";
export [LOCATION_PREFIX, RuntimeChecks] from "checks";
export [library_init_name, library_release_name, LIBRARY_ENTRY_PREFIX] from "globals";
export [initialize_backends, target_triple] from "target";
