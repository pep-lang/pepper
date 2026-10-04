## Bodies a cached unit does not need, dropped:
## `pepper_sema::passes::strip_bodies` in Pepper. After closures are
## lifted, the bodies of the cached files' non-generic functions and
## methods go, with the closure structs lifted out of them; the
## declarations stay, so the rest of the program still resolves them.

import [Loc] from "loc";
import [Block, Expression, FunctionDef, Module, StructDef] from "model";
import [Rewriter, rewrite_block] from "walk";

## Records the closures a body makes.
struct _ClosureNames {
    var names: HashSet<String> = HashSet<String>();

    construct() {}

    rewrite(e: Expression): Expression {
        if (e is MakeClosure(node)) {
            names.insert(node.closure);
        }
        return e;
    }
}

extend _ClosureNames with Rewriter;

## Drops the bodies `module.cached_files` allows: of a cached file's
## function that no generic, trait default or inferred return type needs,
## and whose link summary the cache recorded.
##
## @param module the model, changed in place
export strip_bodies(module: Module) {
    var cached = module.cached_files;
    module.cached_files = Array<bool>();
    bool any = false;
    for (var c in cached) {
        any = any or c;
    }
    if (!any) {
        return;
    }
    var summaries = module.recorded_summaries;
    module.recorded_summaries = HashMap<Loc, String>();
    var dropped = Array<Block>();
    var stripped = HashSet<Loc>();
    var strip = (function: FunctionDef) => {
        var loc = function.loc;
        bool in_cached = !loc.is_none() and (loc.file as ulong) < cached.count and cached[loc.file as ulong];
        if (in_cached
            and function.owner.is_none()
            and function.generic_params.count == 0
            and !function.ty.is_auto()
            and summaries.contains(loc)
            and function.body.is_value()) {
            dropped.append(function.body.value());
            function.body = Optional<Block>.Empty;
            stripped.insert(loc);
        }
    };
    for (var function in module.functions) {
        strip(function);
    }
    for (var st in module.structs) {
        if (st.generic_params.count == 0) {
            for (var method in st.method_members) {
                strip(method);
            }
        }
    }
    for (var ext in module.extensions) {
        if (ext.target.sub_types.count == 0) {
            for (var method in ext.methods) {
                strip(method);
            }
        }
    }
    # The closures those bodies made, and the closures those made.
    var closures = _ClosureNames();
    while (dropped.count > 0) {
        var body = dropped.pop();
        rewrite_block(body, closures);
        for (var st in module.structs) {
            if (closures.names.contains(st.name)) {
                for (var method in st.method_members) {
                    if (method.body.is_value()) {
                        dropped.append(method.body.value());
                        method.body = Optional<Block>.Empty;
                    }
                }
            }
        }
    }
    var kept = Array<StructDef>();
    for (var st in module.structs) {
        if (!closures.names.contains(st.name)) {
            kept.append(st);
        }
    }
    module.structs = kept;
    module.stripped = stripped;
    module.recorded_summaries = summaries;
    module.cached_files = cached;
}
