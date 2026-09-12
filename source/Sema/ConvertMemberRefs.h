
#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::sema {
    struct ConvertMemberRefs : public Transformer {
        DECLARE_RTTI(ConvertMemberRefs, Transformer);

        llvm::StringMap<StructDef*> structs;

        struct ReplaceMemberRefs : Visitor {
            StructDef* struct_def;
            llvm::StringSet<> locals;

            ReplaceMemberRefs(StructDef* st, const llvm::StringSet<>& locals = {})
                : struct_def(st)
                , locals(locals) {}

            void visitNode(NodeRef& node) override {
                if (auto varDef = node->as<VariableDef>()) {
                    if (!varDef->is<FieldDef>())
                        locals.insert(varDef->name);
                    return;
                }
                if (auto symRef = node->as<SymbolRef>()) {
                    if (symRef->is<MemberRef>() || symRef->id == "this")
                        return;
                    if (!locals.contains(symRef->id)) {
                        auto field = Query(struct_def->field_members).find([&](auto& f) { return f->name == symRef->id; });
                        if (!field) {
                            throw CompileError(symRef->source_loc, "Unable to resolve symbol {0}", symRef->id);
                        }
                        Node::push_source(node->source_loc);
                        node = new MemberRef(new ThisRef(), symRef->id);
                        Node::pop_source();
                    }
                }
                if (auto call = node->as<FunctionCall>()) {
                    // convert function calls that are actually method calls
                    if (auto method = struct_def->get_method(call->target.name())) {
                        PEP_TRACE_AST("Convert {0} to this.{0}", call->to_string());
                        Node::push_source(node->source_loc);
                        node = new MethodCall(new SymbolRef("this"), method->name, call->args);
                        Node::pop_source();
                    }
                }
            }
        };

        llvm::StringSet<> GetParams(FunctionDef* function) {
            llvm::StringSet<> params;
            for (const auto& param : function->parameters) {
                params.insert(param.name);
            }
            return params;
        }

        void run(Ref<Module> module) override {
            for (auto& st : module->structs()) {
                ReplaceMemberRefs replaceForCtor{st, GetParams(st->construct)};
                replaceForCtor.visit(st->construct);
                for (auto& method : st->method_members) {
                    ReplaceMemberRefs replaceForMethod{st, GetParams(method)};
                    replaceForMethod.visit(method);
                }
            }
        }
    };
} // namespace pepper::sema
