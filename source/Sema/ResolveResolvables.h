#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveResolvables : public Transformer {
        DECLARE_RTTI(ResolveResolvables, Transformer);

        bool ReportMissing = false;
        SymbolTable Symbols;

        ResolveResolvables(bool reportMissing = false)
            : ReportMissing(reportMissing) {}

        struct ReferenceResolver : Resolver {
            const SymbolTable& Symbols;
            bool ReportMissing;
            Vector<Node*> Stack;

            ReferenceResolver(const SymbolTable& symbols, bool reportMissing)
                : Symbols(symbols)
                , ReportMissing(reportMissing) {}

            Node* current() const {
                return Stack.back();
            }

            void visitResolvable(ResolvableBase& res) override {
                if (res.value())
                    return;

                if (res.type()->is<StructDef>()) {
                    resolveStruct(res);
                } else if (res.type()->is<FunctionNode>() && !res.type()->is<MethodDef>()) {
                    resolveFunction(res);
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
                        resolveMethod(methodCall);
                }
            }

            void resolveStruct(ResolvableBase& res) {
                if (auto structDef = Symbols.Structs.lookup(res.name())) {
                    PEP_TRACE_AST("Resolved {0}/{1} -> {2}", current()->toString(), res.name(), structDef->Name);
                    res.resolve(structDef);
                    return;
                }
                if (ReportMissing)
                    throw CompileError("Unable to resolve {0}", res.name());
            }

            void resolveFunction(ResolvableBase& res) {
                if (auto funcDef = Symbols.Functions.lookup(res.name())) {
                    PEP_TRACE_AST("Resolved {0}/{1} -> {2}", current()->toString(), res.name(), funcDef->Name);
                    res.resolve(funcDef);
                    return;
                }
                if (ReportMissing)
                    throw CompileError("Unable to resolve {0}", res.name());
            }

            void resolveMethod(MethodCall* methodCall) {
                auto structType = methodCall->This->type();

                // If the expression doesn't have a useful type, it could be a static function call
                // so the LHS will be a symbol ref with the name of the class
                if (structType.empty() && methodCall->This->is<SymbolRef>()) {
                    auto ref = methodCall->This->as<SymbolRef>();
                    structType = {ref->Name};
                }
                if (!structType.empty()) {
                    if (auto st = Symbols.Structs.lookup(structType.toString())) {
                        if (auto method = st->getMethod(methodCall->Target.name())) {
                            PEP_TRACE_AST("Resolved {0} -> {1}.{2}", methodCall->toString(), st->Name, method->Name);
                            methodCall->Target.resolve(method);
                            return;
                        }
                    }
                }
                PEP_TRACE_AST("Unable to resolve {0}", methodCall->Target.name());
                if (ReportMissing)
                    throw CompileError("Unable to resolve {0}", methodCall->Target.name());
            }
        };

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);

            ReferenceResolver resolver(Symbols, ReportMissing);
            for (auto& root : parseTree->roots()) {
                // No point in resolving generics, the results won't get used anyway
                if (auto st = root->as<StructDef>()) {
                    if (st->isGeneric())
                        continue;
                }
                if (auto func = root->as<FunctionDef>()) {
                    if (func->isGeneric())
                        continue;
                }
                resolver.visit(root);
            }
        }
    };
} // namespace pepper::ast
