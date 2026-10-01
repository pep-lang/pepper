## The scope protocol behind `with (var x = scope) { ... } else { ... }`.
##
## A `with` block holds `scope` in a hidden local, binds `x` to
## `scope.enter()`, and runs the body. When `enter()` returns a struct
## reference that is null, the body is skipped and the optional `else` block
## runs instead. Both locals are released on every path out of the block
## (falling off the end, `return`, `break`, `continue`), the binding first.
## Cleanup is the scope object's destructor, which calls `exit()`.

# The block lowers to
#
#     {
#         var scope = <expression>;
#         var x = scope.enter();
#         if (x != __null) { body } else { other }   # null test only for a struct result
#     }
#
# `with` goes by the methods a type has, so declaring the trait is optional;
# declaring it (`extend Foo with Scoped<Bar>`) checks the methods.

## Something a `with` block can enter.
##
## `enter()` runs once when the block is entered, and its result is what the
## header binds. `exit()` is the cleanup: implementations call it from their
## destructor (`destruct { this.exit(); }`), so it runs when the scope
## object's last reference is released. For a scope object created in the
## `with` header that is the end of the block; for one that is also held
## elsewhere, it is when that last owner lets go.
##
## A `with` block with no binding (`with (scope) { ... }`) still holds the
## result of `enter()` until the block ends. An `enter()` that returns `void`
## has nothing to bind.
##
## @typeParam T the type `enter()` returns
## @example
##     var open = 0;
##
##     struct Session {
##         construct() {
##             open = open + 1;
##         }
##
##         destruct {
##             this.exit();
##         }
##
##         Session enter() {
##             return this;
##         }
##
##         exit() {
##             open = open - 1;
##         }
##     }
##
##     extend Session with Scoped<Session>;
##
##     main(): int {
##         with (var session = Session()) {
##             # open == 1 here
##         }
##         return open;   # 0: the session was destroyed at the end of the block
##     }
export trait Scoped<T> {
    ## Enters the scope.
    ##
    ## A null struct reference means there is nothing to use: the `with`
    ## body is skipped and its `else` block runs instead.
    ##
    ## @returns the value the `with` header binds
    enter(): T;

    ## Leaves the scope. Implementations call it from their destructor.
    exit();
}
