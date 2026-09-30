## Weak references: `Weak<T>` points at an object without keeping it alive.

# `Weak<T>` wraps the `__weak<T>` intrinsic type (a `std::weak_ptr<T>`):
# every struct object carries a weak count next to its reference count, the
# last strong release destroys the object, and its memory is freed once no
# weak reference remains (passes/weak_types.rs, struct_body.rs).

import "scoped";

## A reference to a struct object that does not keep it alive, for back
## pointers (a child's parent, an observer's subject) that would otherwise
## form a reference cycle and leak.
##
## The object is reached only through a `with` block, which upgrades the weak
## reference to an ordinary strong one for the length of the block. Once the
## object has been destroyed the upgrade fails: the body is skipped and the
## `else` block runs instead.
##
## A `Weak<T>` never changes what it points at, so copies of it can be shared
## freely.
##
## @typeParam T the struct type pointed at
## @example
##     struct Child {
##         Weak<Parent> owner;
##
##         construct(Parent owner) {
##             this.owner = Weak<Parent>(owner);
##         }
##
##         String owner_name() {
##             with (var parent = this.owner) {
##                 return parent.name;
##             } else {
##                 return "(gone)";
##             }
##             return "";
##         }
##     }
## @see Scoped
export struct Weak<T> {
    ## The weak reference itself.
    __weak<T> _target;

    ## Creates a weak reference to `target`'s object.
    ##
    ## @param target the object to point at; a null reference makes a weak reference that is always expired
    construct(target: T) {
        _target = __weak_from<T>(target);
    }

    ## Reports whether the object has been destroyed.
    ##
    ## A `false` result can be out of date by the time it is used; enter the
    ## reference with `with` to use the object.
    ##
    ## @returns true once the object has been destroyed, or if the reference was made from null
    expired(): bool {
        return __weak_expired<T>(_target);
    }

    ## Upgrades the weak reference for a `with` block.
    ##
    ## @returns a new strong reference to the object, or null once it has been destroyed
    enter(): T {
        return __weak_upgrade<T>(_target);
    }

    ## Leaves the scope. The strong reference `enter()` returned is released
    ## by the `with` block itself, so there is nothing to do.
    exit() {}

    ## Leaves the scope; a weak reference has nothing to clean up.
    destruct {
        this.exit();
    }
}
