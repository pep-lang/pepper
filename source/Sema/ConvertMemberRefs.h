
#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::ast {
    struct ConvertMemberRefs : public Transformer {
        DECLARE_RTTI(ConvertMemberRefs, Transformer);

        llvm::StringMap<StructDef*> Structs;

        struct ReplaceMemberRefs : Visitor {
            StructDef* Struct;
            llvm::StringSet<> Locals;

            ReplaceMemberRefs(StructDef* st, const llvm::StringSet<>& locals = {})
                : Struct(st)
                , Locals(locals) {}

            void visitNode(NodeRef& node) override {
                if (auto varDef = node->as<VariableDef>()) {
                    if (!varDef->is<FieldDef>())
                        Locals.insert(varDef->Name);
                    return;
                }
                if (auto symRef = node->as<SymbolRef>()) {
                    if (symRef->is<MemberRef>() || symRef->Name == "this")
                        return;
                    if (!Locals.contains(symRef->Name)) {
                        auto field = Query(Struct->Fields).find([&](auto& f) { return f->Name == symRef->Name; });
                        if (!field) {
                            throw CompileError(symRef->Source, "Unable to resolve symbol {0}", symRef->Name);
                        }
                        Node::PushSource(node->Source);
                        node = new MemberRef(new ThisRef(), symRef->Name);
                        Node::PopSource();
                    }
                }
                if (auto call = node->as<FunctionCall>()) {
                    // convert function calls that are actually method calls
                    if (auto method = Struct->getMethod(call->Target.name())) {
                        PEP_TRACE_AST("Convert {0} to this.{0}", call->toString());
                        Node::PushSource(node->Source);
                        node = new MethodCall(new SymbolRef("this"), method->Name, call->Args);
                        Node::PopSource();
                    }
                }
            }
        };

        llvm::StringSet<> GetParams(FunctionDef* function) {
            llvm::StringSet<> params;
            for (const auto& param : function->Parameters) {
                params.insert(param.Name);
            }
            return params;
        }

        void run(Ref<AST> parseTree) override {
            for (auto& st : parseTree->structs()) {
                ReplaceMemberRefs replaceForCtor{st, GetParams(st->Constructor)};
                replaceForCtor.visit(st->Constructor);
                for (auto& method : st->Methods) {
                    ReplaceMemberRefs replaceForMethod{st, GetParams(method)};
                    replaceForMethod.visit(method);
                }
            }
        }
    };
} // namespace pepper::ast
