## Every place the model holds code: a field's or a module-scope variable's
## initializer, and the parameter defaults and body of a constructor,
## method, generic method, destructor, free function, extension method or
## trait default method. Passes walk them with `for_each_place` (or
## `rewrite_places`), so each meets every place, and a new kind of place is
## added here once.

import [unit_decls] from "checked";
import [Expression, ExtensionDef, FunctionDef, Module, StructDef, TypeName, VariableDef] from "model";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## What holds a place's code.
export enum PlaceKind {
    ## A field's initializer.
    Field,
    ## A constructor, method or destructor of a struct.
    Member,
    ## A generic method of a struct, which `specialize_methods` clones.
    GenericMethod,
    ## A free function.
    Function,
    ## An extension's own copy of its method, which `apply_extensions`
    ## clones onto its target.
    Extension,
    ## A trait's default method, which `apply_extensions` copies into the
    ## structs that take it.
    TraitDefault,
    ## A module-scope variable's initializer.
    Global,
}

## One place, as `for_each_place` hands it out.
export struct Place {
    ## What holds the code.
    var kind: PlaceKind;
    ## The struct the code is a member of: a field's, member's or generic
    ## method's.
    var owner: StructDef?;
    ## The type `this` has in the code: the owner's, an extension's
    ## target, or a trait's name.
    var this_type: TypeName?;
    ## The function whose parameter defaults and body the place is.
    var function: FunctionDef?;
    ## The field or module-scope variable whose initializer the place is.
    var variable: VariableDef?;
    ## The extension whose own copy of a method the place is.
    var extension: ExtensionDef?;

    ## Makes a place.
    ##
    ## @param kind what holds the code
    ## @param owner the struct the code is a member of
    ## @param this_type the type `this` has in the code
    ## @param function the function, for a function's place
    ## @param variable the variable, for an initializer's place
    ## @param extension the extension, for an extension method's place
    construct(
        kind: PlaceKind,
        owner: StructDef?,
        this_type: TypeName?,
        function: FunctionDef? = Optional<FunctionDef>.Empty,
        variable: VariableDef? = Optional<VariableDef>.Empty,
        extension: ExtensionDef? = Optional<ExtensionDef>.Empty
    ) {
        this.kind = kind;
        this.owner = owner;
        this.this_type = this_type;
        this.function = function;
        this.variable = variable;
        this.extension = extension;
    }

    ## Returns whether the code is a generic base: a generic free function,
    ## a member of a generic struct's base, or a generic method. Its
    ## specializations are concrete.
    ##
    ## @returns whether the code is generic
    is_generic(): bool {
        if (kind == PlaceKind.GenericMethod or kind == PlaceKind.TraitDefault) {
            return true;
        }
        if (function.is_value() and function.value().is_generic_func) {
            return true;
        }
        if (owner.is_value()) {
            var st = owner.value();
            return st.ty.is_generic() and st.name == st.ty.name;
        }
        return false;
    }

    ## Applies `rewriter` to every expression of the place: a function's
    ## parameter defaults, then its body, or an initializer.
    ##
    ## @param rewriter what to do at each expression
    rewrite(rewriter: Rewriter) {
        if (variable.is_value()) {
            var v = variable.value();
            if (v.default.is_value()) {
                v.default = Optional<Expression>.Value(rewrite_expression(v.default.value(), rewriter));
            }
            return;
        }
        var f = function.value();
        for (var p in f.parameters) {
            if (p.default.is_value()) {
                p.default = Optional<Expression>.Value(rewrite_expression(p.default.value(), rewriter));
            }
        }
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), rewriter);
        }
    }
}

## What a walk over the places does at each.
export trait PlaceVisitor {
    ## Visits one place.
    ##
    ## @param place the place
    visit(place: Place);
}

## Hands `visitor` each place of `module`, in this order: per struct, the
## fields with an initializer, the methods, the constructors, the
## destructor and the generic methods; the free functions; the extensions'
## methods; the traits' default methods; the module-scope variables with an
## initializer.
##
## @param module the model
## @param visitor what to do at each place
## @param unit only the compilation unit's own structs and functions (`unit_decls`), not the checked ones
## @param extensions the extensions' own copies of their methods too
## @param templates the code other code is copied from too: generic methods and trait default methods
## @param fields the fields' own initializers too, which `synthesize` copied into each constructor: the passes after it read them only for a field's type, and a specialization keeps its base's
export for_each_place(
    module: Module,
    visitor: PlaceVisitor,
    unit: bool = false,
    extensions: bool = true,
    templates: bool = false,
    fields: bool = true
) {
    var structs = module.structs;
    var functions = module.functions;
    if (unit) {
        var decls = unit_decls(module);
        structs = decls.structs;
        functions = decls.functions;
    }
    var none = Optional<StructDef>.Empty;
    for (var st in structs) {
        var owner = Optional<StructDef>.Value(st);
        var this_type = Optional<TypeName>.Value(st.ty);
        for (var field in st.field_members) {
            if (fields and field.default.is_value()) {
                visitor.visit(Place(PlaceKind.Field, owner, this_type, variable = Optional<VariableDef>.Value(field)));
            }
        }
        for (var method in st.method_members) {
            visitor.visit(Place(PlaceKind.Member, owner, this_type, Optional<FunctionDef>.Value(method)));
        }
        for (var c in st.constructors) {
            visitor.visit(Place(PlaceKind.Member, owner, this_type, Optional<FunctionDef>.Value(c)));
        }
        visitor.visit(Place(PlaceKind.Member, owner, this_type, Optional<FunctionDef>.Value(st.destructor)));
        if (templates) {
            for (var method in st.generic_methods) {
                visitor.visit(Place(PlaceKind.GenericMethod, owner, this_type, Optional<FunctionDef>.Value(method)));
            }
        }
    }
    var no_type = Optional<TypeName>.Empty;
    for (var function in functions) {
        visitor.visit(Place(PlaceKind.Function, none, no_type, Optional<FunctionDef>.Value(function)));
    }
    if (extensions) {
        for (var ext in module.extensions) {
            var target = Optional<TypeName>.Value(ext.target);
            var extension = Optional<ExtensionDef>.Value(ext);
            for (var method in ext.methods) {
                visitor.visit(
                    Place(PlaceKind.Extension, none, target, Optional<FunctionDef>.Value(method), extension = extension)
                );
            }
        }
    }
    if (templates) {
        for (var t in module.traits) {
            var trait_type = Optional<TypeName>.Value(TypeName.named(t.name));
            for (var method in t.methods) {
                visitor.visit(Place(PlaceKind.TraitDefault, none, trait_type, Optional<FunctionDef>.Value(method)));
            }
        }
    }
    for (var global in module.globals) {
        if (global.default.is_value()) {
            visitor.visit(Place(PlaceKind.Global, none, no_type, variable = Optional<VariableDef>.Value(global)));
        }
    }
}

## Applies `rewriter` to every expression of every place `for_each_place`
## hands out with the same options.
##
## @param module the model
## @param rewriter what to do at each expression
## @param unit only the compilation unit's own structs and functions
## @param extensions the extensions' own copies of their methods too
## @param templates generic methods and trait default methods too
export rewrite_places(
    module: Module, rewriter: Rewriter, unit: bool = false, extensions: bool = true, templates: bool = false
) {
    for_each_place(module, _RewriteEach(rewriter), unit, extensions, templates);
}

## Applies `rewriter` to every expression of concrete code: each place but
## the generic bases (`Place.is_generic`), whose specializations are
## walked instead, and the extensions' own copies of their methods, whose
## targets' copies are.
##
## @param module the model
## @param rewriter what to do at each expression
export rewrite_concrete_places(module: Module, rewriter: Rewriter) {
    for_each_place(module, _RewriteEach(rewriter, true), extensions = false, fields = false);
}

## Rewrites each place it visits, or each concrete one.
struct _RewriteEach {
    var rewriter: Rewriter;
    var concrete: bool;

    construct(rewriter: Rewriter, concrete: bool = false) {
        this.rewriter = rewriter;
        this.concrete = concrete;
    }

    visit(place: Place) {
        if (!concrete or !place.is_generic()) {
            place.rewrite(rewriter);
        }
    }
}

extend _RewriteEach with PlaceVisitor;
