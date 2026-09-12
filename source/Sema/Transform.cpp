
#include "Transform.h"

#include "Core/Messages.h"
#include "Sema/ApplyExtensions.h"
#include "Sema/ConvertIntrinsics.h"
#include "Sema/ConvertMemberRefs.h"
#include "Sema/ConvertStringLiterals.h"
#include "Sema/GatherGenerics.h"
#include "Sema/ReleaseFieldRefs.h"
#include "Sema/ResolveImplicitTypes.h"
#include "Sema/ResolveLiterals.h"
#include "Sema/ResolveOperators.h"
#include "Sema/ResolveResolvables.h"
#include "Sema/SpecializeFunctions.h"
#include "Sema/SpecializeStructs.h"
#include "Sema/TagGenerics.h"

namespace pepper::sema {
    TransformPass::TransformPass(Ref<Module> module)
        : module(module) {
        // First pass
        transformers.emplace_back(new ResolveLiterals());
        transformers.emplace_back(new TagGenerics());
        transformers.emplace_back(new ConvertStringLiterals());
        transformers.emplace_back(new GatherGenerics());
        transformers.emplace_back(new ResolveImplicitTypes());
        transformers.emplace_back(new ResolveResolvables());   // resolve as much as possible
        transformers.emplace_back(new ApplyExtensions(false)); // apply generic/concrete extensions
        transformers.emplace_back(new SpecializeStructs());
        transformers.emplace_back(new SpecializeFunctions());
        transformers.emplace_back(new ConvertIntrinsics());
        transformers.emplace_back(new ResolveResolvables());  // resolve what remains
        transformers.emplace_back(new ApplyExtensions(true)); // apply specialized extensions
        transformers.emplace_back(new ConvertMemberRefs());
        transformers.emplace_back(new ResolveImplicitTypes());
        transformers.emplace_back(new ResolveOperators());

        // Second pass, resolve dependent types/calls
        transformers.emplace_back(new GatherGenerics());
        transformers.emplace_back(new SpecializeStructs());
        transformers.emplace_back(new SpecializeFunctions());
        transformers.emplace_back(new ConvertIntrinsics());
        transformers.emplace_back(new ResolveResolvables());
        transformers.emplace_back(new ConvertMemberRefs());

        // final pass
        transformers.emplace_back(new ReleaseFieldRefs());
        transformers.emplace_back(new ResolveImplicitTypes());
        transformers.emplace_back(
            new ResolveOperators()); // Once implicit types are resolved, operator overloading may exist
        transformers.emplace_back(new ResolveResolvables(true));
    }

    Ref<Module> TransformPass::run() const {
        for (auto& xform : transformers) {
            PEP_TRACE_AST("Begin {0}", xform->rtti()->name());
            Messages::indent(TraceChannel::AST);
            xform->run(module);
            Messages::outdent(TraceChannel::AST);
            PEP_TRACE_AST("End {0}", xform->rtti()->name());
        }
        return module;
    }

    SymbolTable::SymbolTable()
        : types(TypeName::IntegralTypes) {}

#define TRACE_SYMBOL(...)

    // #define TRACE_SYMBOL PEP_TRACE_AST

    SymbolTable::SymbolTable(const Module& module)
        : SymbolTable() {
        TRACE_SYMBOL("### Symbol Table Begin ###");
        Messages::indent(TraceChannel::AST);
        for (auto& function : module.functions()) {
            if (!functions.lookup(function->name)) {
                // First function with any given name is the generic base (if it's generic)
                functions[function->name] = function;
                TRACE_SYMBOL("Function: {0} -> {1}", function->name, function->type.to_string());
            } else {
                functions[function->name] = function;
                TRACE_SYMBOL("Function: {0} -> {1}", function->name, function->type.to_string());
            }
        }

        for (auto& extern_function : module.externs()) {
            functions[extern_function->name] = extern_function;
        }

        for (auto& st : module.structs()) {
            structs[st->name] = st;
            if (st->is_generic()) {
                structs[st->type.to_string()] = st;
                TRACE_SYMBOL("Struct: {0} -> {1}", st->name, st->type.to_string());
            } else {
                TRACE_SYMBOL("Struct: {0}", st->name);
            }

            Messages::indent(TraceChannel::AST);

            functions[st->construct->name] = st->construct;
            TRACE_SYMBOL("Constructor {0}: {1}", st->name, st->construct->name);

            for (auto& method : st->method_members) {
                TRACE_SYMBOL("{0}.{1}", st->name, method->name);
            }
            Messages::outdent(TraceChannel::AST);
        }

        for (auto& trait : module.traits()) {
            traits[trait->name] = trait;
        }

        Messages::outdent(TraceChannel::AST);
        TRACE_SYMBOL("### Symbol Table End ###");
    }

    Symbol* SymbolTable::find(const Ident& name) const {
        if (auto fn = functions.lookup(name))
            return fn;
        return structs.lookup(name);
    }

    TypeName SymbolTable::find(const TypeName& name) const {
        if (types.contains(name.to_string()))
            return name;
        if (structs.lookup(name.to_string()))
            return name;
        return {};
    }
} // namespace pepper::sema
