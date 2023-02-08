
#include "Transform.h"

#include "Core/Messages.h"
#include "Sema/ApplyExtensions.h"
#include "Sema/ConvertIntrinsics.h"
#include "Sema/ConvertMemberRefs.h"
#include "Sema/ConvertStringLiterals.h"
#include "Sema/GatherGenerics.h"
#include "Sema/ReleaseFieldRefs.h"
#include "Sema/ResolveImplicitTypes.h"
#include "Sema/ResolveOperators.h"
#include "Sema/ResolveResolvables.h"
#include "Sema/SpecializeFunctions.h"
#include "Sema/SpecializeStructs.h"
#include "Sema/TagGenerics.h"

namespace pepper::ast {
    TransformPass::TransformPass(Ref<AST> parseTree)
        : ParseTree(parseTree) {
        // First pass
        Transformers.emplace_back(new TagGenerics());
        Transformers.emplace_back(new ConvertStringLiterals());
        Transformers.emplace_back(new GatherGenerics());
        Transformers.emplace_back(new ResolveImplicitTypes());
        Transformers.emplace_back(new ResolveResolvables());   // resolve as much as possible
        Transformers.emplace_back(new ApplyExtensions(false)); // apply generic/concrete extensions
        Transformers.emplace_back(new SpecializeStructs());
        Transformers.emplace_back(new SpecializeFunctions());
        Transformers.emplace_back(new ConvertIntrinsics());
        Transformers.emplace_back(new ResolveResolvables());  // resolve what remains
        Transformers.emplace_back(new ApplyExtensions(true)); // apply specialized extensions
        Transformers.emplace_back(new ConvertMemberRefs());
        Transformers.emplace_back(new ResolveImplicitTypes());
        Transformers.emplace_back(new ResolveOperators());

        // Second pass, resolve dependent types/calls
        Transformers.emplace_back(new GatherGenerics());
        Transformers.emplace_back(new SpecializeStructs());
        Transformers.emplace_back(new SpecializeFunctions());
        Transformers.emplace_back(new ConvertIntrinsics());
        Transformers.emplace_back(new ResolveResolvables());
        Transformers.emplace_back(new ConvertMemberRefs());

        // final pass
        Transformers.emplace_back(new ReleaseFieldRefs());
        Transformers.emplace_back(new ResolveImplicitTypes());
        Transformers.emplace_back(new ResolveResolvables(true));
    }

    Ref<AST> TransformPass::run() const {
        for (auto& xform : Transformers) {
            PEP_TRACE_AST("Begin {0}", xform->rtti()->name());
            Messages::Indent(TraceChannel::AST);
            xform->run(ParseTree);
            Messages::Outdent(TraceChannel::AST);
            PEP_TRACE_AST("End {0}", xform->rtti()->name());
        }
        return ParseTree;
    }

    SymbolTable::SymbolTable()
        : Types(TypeName::IntegralTypes) {}

#define TRACE_SYMBOL(...)

    // #define TRACE_SYMBOL PEP_TRACE_AST

    SymbolTable::SymbolTable(const AST& ast)
        : SymbolTable() {
        TRACE_SYMBOL("### Symbol Table Begin ###");
        Messages::Indent(TraceChannel::AST);
        for (auto& function : ast.functions()) {
            if (!Functions.lookup(function->Name)) {
                // First function with any given name is the generic base (if it's generic)
                Functions[function->Name] = function;
                TRACE_SYMBOL("Function: {0} -> {1}", function->Name, function->Type.toString());
            } else {
                Functions[function->Name] = function;
                TRACE_SYMBOL("Function: {0} -> {1}", function->Name, function->Type.toString());
            }
        }

        for (auto& externFunction : ast.externs()) {
            Functions[externFunction->Name] = externFunction;
        }

        for (auto& st : ast.structs()) {
            Structs[st->Name] = st;
            if (st->isGeneric()) {
                Structs[st->Type.toString()] = st;
                TRACE_SYMBOL("Struct: {0} -> {1}", st->Name, st->Type.toString());
            } else {
                TRACE_SYMBOL("Struct: {0}", st->Name);
            }

            Messages::Indent(TraceChannel::AST);

            Functions[st->Constructor->Name] = st->Constructor;
            TRACE_SYMBOL("Constructor {0}: {1}", st->Name, st->Constructor->Name);

            for (auto& method : st->Methods) {
                TRACE_SYMBOL("{0}.{1}", st->Name, method->Name);
            }
            Messages::Outdent(TraceChannel::AST);
        }

        for (auto& trait : ast.traits()) {
            TraitDecls[trait->Name] = trait;
        }

        Messages::Outdent(TraceChannel::AST);
        TRACE_SYMBOL("### Symbol Table End ###");
    }

    Symbol* SymbolTable::find(const Ident& name) const {
        if (auto fn = Functions.lookup(name))
            return fn;
        return Structs.lookup(name);
    }

    TypeName SymbolTable::find(const TypeName& name) const {
        if (Types.contains(name.toString()))
            return name;
        if (Structs.lookup(name.toString()))
            return name;
        return {};
    }
} // namespace pepper::ast
