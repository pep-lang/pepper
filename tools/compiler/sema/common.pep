## What the passes share: diagnostics at model locations, and the facts the
## Rust model's methods give about its declarations.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [Loc] from "loc";
import [StructDef] from "model";

## Returns `loc` as a diagnostic's location.
##
## @param loc the location
## @returns the diagnostic location
export location_of(loc: Loc): Location {
    return Location(loc.file as ulong, loc.span);
}

## Returns the error `message` at `loc`.
##
## @param message the message
## @param loc where it points
## @returns the diagnostic
export error_at(message: String, loc: Loc): Diagnostic {
    return Diagnostic.error(message).at(location_of(loc));
}

## The facts `StructDef`'s methods give in the Rust model.
export extend StructDef {
    ## Returns whether this is a value type (`[Value]`): copied, not
    ## counted.
    ##
    ## @returns true for a value type
    is_value(): bool {
        return has_bare_attribute(attributes, VALUE_ATTRIBUTE);
    }
}
