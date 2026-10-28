# A package whose folder holds a toolchain (#284): its `Value` is the
# runtime's attribute `Value` again, so a build that took the runtime's
# files for this module's would fail with a redefinition.
export enum Value {
    A,
}
