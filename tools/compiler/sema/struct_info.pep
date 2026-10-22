## What a value of a struct or trait type has, as `StructTable` files it:
## apart from `static_type` so that the passes' state can keep the checked
## structs' entries (`TraitTypeMemo.infos`) without importing that pass.

import [FunctionDef, TypeName] from "model";
import [set_name] from "names";

## What a value of a struct (or trait) type has.
export struct StructInfo {
    ## Its fields and their types, in order.
    var fields: Array<(String, TypeName)> = Array<(String, TypeName)>();
    ## Its method names; an overloaded method also answers to its set's
    ## name.
    var methods: HashSet<String> = HashSet<String>();
    ## Method name to return type.
    var returns: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## The unary operators declared: `-`, `~`, `!`, `!!` as instance
    ## methods without parameters.
    var unary_operators: HashSet<String> = HashSet<String>();
    ## A generic base's own type parameters, which its fields' and
    ## methods' types are written in.
    var params: Array<String> = Array<String>();
    ## Its generic methods, as declared (`pass<T>`).
    var generic_methods: FunctionDef[] = Array<FunctionDef>();

    construct() {}

    ## Returns the type of field `name`, or none.
    field(name: String): TypeName? {
        for (var (f, ty) in fields) {
            if (f == name) {
                return Optional<TypeName>.Value(ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    _add_methods(methods: FunctionDef[]) {
        for (var m in methods) {
            this.methods.insert(m.name);
            this.methods.insert(set_name(m.name));
            returns[m.name] = m.ty;
            if (!m.is_static and m.parameters.count == 0) {
                var at = m.name.find("$");
                var base = at < 0 ? m.name : m.name.substr_bytes(0, at as ulong);
                if (base == "-" or base == "~" or base == "!" or base == "!!") {
                    unary_operators.insert(base);
                }
            }
        }
    }
}
