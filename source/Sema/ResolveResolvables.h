#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ResolveResolvables : public Transformer {
        DECLARE_RTTI(ResolveResolvables, Transformer);

        bool report_missing = false;
        SymbolTable symbols;

        ResolveResolvables(bool should_report_missing = false)
            : report_missing(should_report_missing) {}

        struct ReferenceResolver : Resolver {
            const SymbolTable& symbols;
            bool report_missing;
            Vector<Node*> Stack;

            ReferenceResolver(const SymbolTable& symbols, bool should_report_missing)
                : symbols(symbols)
                , report_missing(should_report_missing) {}

            Node* current() const {
                return Stack.back();
            }

            void visitResolvable(ResolvableBase& res) override {
                if (res.value())
                    return;

                if (res.type()->is<StructDef>()) {
                    resolve_struct(res);
                } else if (res.type()->is<FunctionNode>() && !res.type()->is<MethodDef>()) {
                    resolve_function(res);
                }
            }

            void enterNode(NodeRef& node) override {
                Stack.emplace_back(node);
            }

            void exitNode(NodeRef&) override {
                Stack.pop_back();
            }

            void visitNode(NodeRef& node) override {
                if (auto methodCall = node->as<MethodCall>()) {
                    if (!methodCall->Target.value())
                        resolve_method(methodCall);
                }
            }

            void resolve_struct(ResolvableBase& res) {
                if (auto structDef = symbols.structs.lookup(res.name())) {
                    PEP_TRACE_AST(
                        "Resolved Struct {0}/{1} -> {2}", current()->to_string(), res.name(), structDef->name);
                    res.resolve(structDef);
                    return;
                }
                if (report_missing)
                    throw CompileError("Unable to resolve Struct {0}", res.name());
            }

            void resolve_function(ResolvableBase& res) {
                if (auto funcDef = symbols.functions.lookup(res.name())) {
                    PEP_TRACE_AST(
                        "Resolved function {0}/{1} -> {2}", current()->to_string(), res.name(), funcDef->name);
                    res.resolve(funcDef);
                    return;
                }
                if (report_missing)
                    throw CompileError("Unable to resolve function {0}", res.name());
            }

            void resolve_method(MethodCall* methodCall) {
                auto structType = methodCall->This->type();

                // If the expression doesn't have a useful type, it could be a static function call
                // so the lhs will be a symbol ref with the name of the class
                if (structType.empty() && methodCall->This->is<SymbolRef>()) {
                    auto ref = methodCall->This->as<SymbolRef>();
                    structType = {ref->id};
                }
                if (!structType.empty()) {
                    if (auto st = symbols.structs.lookup(structType.to_string())) {
                        if (auto method = st->get_method(methodCall->Target.name())) {
                            PEP_TRACE_AST(
                                "Resolved Method {0} -> {1}.{2}", methodCall->to_string(), st->name, method->name);
                            methodCall->Target.resolve(method);
                            return;
                        }
                    }
                }
                PEP_TRACE_AST(
                    "Unable to resolve Method {0} @ {1}", methodCall->to_string(), methodCall->source_loc.to_string());
                if (report_missing)
                    throw CompileError("Unable to resolve Method {0}", methodCall->Target.name());
            }
        };

        void run(Ref<Module> module) override {
            symbols = SymbolTable(*module);

            ReferenceResolver resolver(symbols, report_missing);
            for (auto& root : module->roots()) {
                // No point in resolving generics, the results won't get used anyway
                if (auto st = root->as<StructDef>()) {
                    if (st->is_generic())
                        continue;
                }
                if (auto func = root->as<FunctionDef>()) {
                    if (func->is_generic())
                        continue;
                }
                resolver.visit(root);
            }
        }
    };
} // namespace pepper::sema
