## A struct's destructor releases its struct fields: `release_field_refs`.

import "apply_extensions";
import "function_types";
import [Loc] from "loc";
import [Expression, MemberRefExpression, MethodCallExpression, Module, Statement] from "model";
import [PassState] from "state";

## Appends to each struct's synthesized `__dtor` a `__release()` of each
## field that holds a struct or a trait value, in reverse declaration
## order, after the user's destructor body. The checked runtime's structs
## have theirs already.
##
## @param module the model, changed in place
## @param state the passes' state, which knows the enums
export release_field_refs(module: Module, state: PassState) {
    var names = HashSet<String>();
    for (var st in module.structs) {
        names.insert(st.name);
        names.insert(st.ty.to_string());
    }
    for (var st in module.structs) {
        if (module.checked.structs.contains(st.name)) {
            continue;
        }
        var fields = Array<String>();
        for (var f in st.field_members) {
            # A trait value releases through its vtable.
            if (_is_struct_type(f.ty, state) and (names.contains(f.ty.to_string()) or _is_trait_type(module, f.ty))) {
                fields.append(f.name);
            }
        }
        if (fields.count == 0) {
            continue;
        }
        # Code generation emits method bodies from `method_members`, where
        # the synthesized `__dtor` lives.
        for (var m in st.method_members) {
            if (m.name != "__dtor") {
                continue;
            }
            if (m.body.is_value()) {
                var body = m.body.value();
                ulong i = fields.count;
                while (i > 0) {
                    i -= 1;
                    var field = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, fields[i], Loc.none()));
                    body.items.append(
                        Statement.Expression(
                            Expression.MethodCall(
                                MethodCallExpression(field, "__release", Array<Expression>(), Loc.none())
                            )
                        )
                    );
                }
            }
            break;
        }
    }
}
