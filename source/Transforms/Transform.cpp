//
// Created by Justin Boswell on 1/5/23.
//

#include "Transforms/Transform.h"

#include "Core/Messages.h"
#include "Transforms/ApplyExtensions.h"
#include "Transforms/ConvertMemberRefs.h"
#include "Transforms/GatherGenerics.h"
#include "Transforms/ReleaseFieldRefs.h"
#include "Transforms/ResolveImplicitTypes.h"
#include "Transforms/ResolveResolvables.h"
#include "Transforms/SpecializeFunctions.h"
#include "Transforms/SpecializeStructs.h"

namespace pepper::ast {
    TransformPass::TransformPass(Ref<AST> parseTree)
        : ParseTree(parseTree) {
        Transformers.emplace_back(new GatherGenerics());
        Transformers.emplace_back(new ResolveResolvables());   // resolve as much as possible
        Transformers.emplace_back(new ApplyExtensions(false)); // apply generic/concrete extensions
        Transformers.emplace_back(new SpecializeStructs());
        Transformers.emplace_back(new SpecializeFunctions());
        Transformers.emplace_back(new ResolveResolvables());  // resolve what remains
        Transformers.emplace_back(new ApplyExtensions(true)); // apply specialized extensions
        Transformers.emplace_back(new ConvertMemberRefs());
        Transformers.emplace_back(new ResolveImplicitTypes());
        Transformers.emplace_back(new ReleaseFieldRefs());
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

    SymbolTable::SymbolTable(const AST& ast) {
        PEP_TRACE_AST("### Symbol Table Begin ###");
        Messages::Indent(TraceChannel::AST);
        for (auto& function : ast.functions()) {
            Functions[function->Name] = function;
            PEP_TRACE_AST("Function: {0}", function->Name);
        }
        for (auto& st : ast.structs()) {
            Structs[st->Name] = st;
            PEP_TRACE_AST("Struct: {0}", st->Name);
            Messages::Indent(TraceChannel::AST);
            if (st->isGeneric()) {
                Structs[st->Type.toString()] = st;
                PEP_TRACE_AST("Struct: {0} -> {1}", st->Type.toString(), st->Name);
            }

            Functions[st->Constructor->Name] = st->Constructor;
            PEP_TRACE_AST("Struct: Constructor {0}: {1}", st->Name, st->Constructor->Name);
            Messages::Outdent(TraceChannel::AST);
        }
        Messages::Outdent(TraceChannel::AST);
        PEP_TRACE_AST("### Symbol Table End ###");
    }

    Symbol* SymbolTable::find(const Ident& name) const {
        if (auto fn = Functions.lookup(name))
            return fn;
        return Structs.lookup(name);
    }
} // namespace pepper::ast
