## Addresses and the frame of the function being generated.

import llvm;
import [AUTO] from compiler.sema;
import "calls";
import "checks";
import "expressions";
import "functions";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

## A named address (an alloca or a field's address) with its Pepper type
## name and LLVM type, which loads need with opaque pointers.
export struct Address {
    var name: String;
    var ty: String;
    var llvm_ty: llvm.Type? = Optional<llvm.Type>.Empty;
    var ptr: llvm.Value;

    construct(name: String, ty: String, ptr: llvm.Value) {
        this.name = name;
        this.ty = ty;
        this.ptr = ptr;
    }

    static typed(name: String, ty: String, llvm_ty: llvm.Type, ptr: llvm.Value): Address {
        var address = Address(name, ty, ptr);
        address.llvm_ty = Optional<llvm.Type>.Value(llvm_ty);
        return address;
    }

    ## A copy at another pointer, keeping the types.
    at(ptr: llvm.Value): Address {
        var address = Address(name, ty, ptr);
        address.llvm_ty = llvm_ty;
        return address;
    }

    ## Loads the current value, or none when the slot's LLVM type is not
    ## known.
    load(builder: llvm.Builder): llvm.Value? {
        if (!llvm_ty.is_value()) {
            return Optional<llvm.Value>.Empty;
        }
        return Optional<llvm.Value>.Value(builder.load(llvm_ty.value(), ptr, name));
    }

    ## Stores `value`, which must have the slot's LLVM type.
    store(builder: llvm.Builder, value: llvm.Value): Result<void> {
        if (llvm_ty.is_value()) {
            check_store_type(llvm_ty.value(), value, name, ty)?;
        }
        builder.store(value, ptr);
        return Result<void>.ok();
    }
}

## Checks that `value` has exactly the LLVM type `slot_ty` of the slot it is
## about to be stored into, which is named `name` and has Pepper type
## `pepper_ty`: LLVM accepts a store of any type through an opaque pointer,
## so a mismatch would otherwise corrupt the neighboring memory.
export check_store_type(slot_ty: llvm.Type, value: llvm.Value, name: String, pepper_ty: String): Result<void> {
    var value_ty = value.value_type();
    if (value_ty.same(slot_ty)) {
        return Result<void>.ok();
    }
    # A `var` whose type inference never resolved reaches codegen as
    # `__auto` (#471), which the user can work around.
    if (pepper_ty == AUTO) {
        return Result<void>.err(Error($"cannot infer the type of '{name}'; write its type in place of 'var'"));
    }
    return Result<void>.err(
        Error(
            $"internal error: storing a value of LLVM type '{value_ty.to_string()}' into '{name}' ('{pepper_ty}', LLVM type '{slot_ty.to_string()}')"
        )
    );
}

## The function being generated: its entry and return blocks, its return
## slot, and its locals.
export struct Frame {
    var function: llvm.Value? = Optional<llvm.Value>.Empty;
    var return_block: llvm.BasicBlock? = Optional<llvm.BasicBlock>.Empty;
    var retval: llvm.Value? = Optional<llvm.Value>.Empty;
    var retval_type: String = "";
    var locals: Array<(String, Address)> = Array<(String, Address)>();
    ## The innermost enclosing loop's `(continue, break)` blocks.
    var loop_break: Optional<(llvm.BasicBlock, llvm.BasicBlock)> = Optional<(llvm.BasicBlock, llvm.BasicBlock)>.Empty;
    ## The index of the innermost enclosing loop's body scope.
    var loop_base_depth: ulong? = Optional<ulong>.Empty;
    ## Whether the current region has emitted a `return`, `break` or
    ## `continue`: the rest of it is dead.
    var exited: bool = false;

    construct() {}

    find_local(name: String): Address? {
        var index = locals.count;
        while (index > 0) {
            index -= 1;
            var (local, address) = locals[index];
            if (local == name) {
                return Optional<Address>.Value(address);
            }
        }
        return Optional<Address>.Empty;
    }

    push_local(name: String, address: Address) {
        locals.append((name, address));
    }
}
