#pragma once

#include <llvm/Support/Format.h>

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveOperators : Transformer {
        DECLARE_RTTI(ResolveOperators, Transformer);

        struct IndexResolver : Visitor {
            SymbolTable Symbols;

            IndexResolver(const SymbolTable& symbols)
                : Symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*>(node)
                    .Case<BinaryOp>([&](auto) { resolveBinaryOp(node); })
                    .Case<UnaryOp>([&](auto) { resolveUnaryOp(node); })
                    .Case<Index>([&](auto) { resolveIndex(node); });
            }

            void resolveBinaryOp(NodeRef& binOp) {
                auto op = binOp->as<BinaryOp>();
                auto lhs = op->LHS;
                // If the LHS is not a struct, it can't be overloaded
                if (!lhs->type().isStruct()) {
                    return;
                }

                // Special case assign to index operations -> __index_set
                if (auto assign = op->as<Assign>()) {
                    if (auto indexSet = lhs->as<Index>()) {
                        auto container = indexSet->LHS;
                        auto st = Symbols.Structs.lookup(container->type().toString());
                        if (st) {
                            // replace x[y] += z with :
                            // tmp = x.__index_get(y)
                            // x.__index_set(y, tmp += z)
                            Node::PushSource(binOp->Source);
                            auto get = new MethodCall(container, {"__index_get"}, {indexSet->IndexExpr});
                            auto tmpName =
                                llvm::formatv("_tmp_{0}_{1}", binOp->Source.Line, binOp->Source.Column).str();
                            auto tmp = new VariableDef(get->type(), tmpName, get);
                            binOp = tmp;
                            auto tmpRef = new SymbolRef(tmpName);
                            assign->LHS = tmpRef;
                            auto set = new MethodCall(container, {"__index_set"}, {indexSet->IndexExpr, assign});
                            block()->Items.insert_after(binOp, set);
                            Node::PopSource();
                        }
                        // if the LHS indexed type isn't a struct, then this must be an indexed access or POD type
                        // and resolveIndex will fix it up
                    }
                }
            }

            void resolveUnaryOp(NodeRef& unOp) {
                // TODO
            }

            void resolveIndex(NodeRef& idxOp) {
                auto op = idxOp->as<Index>();
                auto lhs = op->LHS;
                auto st = Symbols.Structs.lookup(lhs->type().toString());
                if (st) {
                    if (st->getMethod("__index_get")) {
                        // Replace the idx op with a call to the index method
                        Node::PushSource(idxOp->Source);
                        idxOp = new MethodCall(lhs, {"__index_get"}, {op->IndexExpr});
                        Node::PopSource();
                        return;
                    }
                    throw CompileError(idxOp->Source, "No index operator `[]` found for type {0}", st->Name);
                }
                // must be a POD type array, use the default indexing
                idxOp = new ArrayIndex(lhs->type(), {lhs, op->IndexExpr});
            }
        };

        struct OperatorResolver : public Visitor {
            SymbolTable Symbols;

            OperatorResolver(const SymbolTable& symbols)
                : Symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*, void>(node)
                    .Case<BinaryOp>([&](auto) { resolveBinaryOp(node); })
                    .Case<UnaryOp>([&](auto) { resolveUnaryOp(node); });
            }

            void resolveBinaryOp(NodeRef& binOp) {
                auto op = binOp->as<BinaryOp>();
                auto lhs = op->LHS;
                // If the LHS is not a struct, it can't be overloaded
                if (!lhs->type().isStruct()) {
                    return;
                }

                // Resolve any overloads on LHS
                auto opName = op->opName();
                if (!opName.empty()) {
                    auto st = Symbols.Structs.lookup(lhs->type().toString());
                    if (st) {
                        binOp = new MethodCall(lhs, {opName}, {op->RHS});
                    }
                }
            }

            void resolveUnaryOp(NodeRef& unOp) {
                // TODO
            }
        };

        void run(Ref<AST> parseTree) override {
            // Index operations need to be resolved first so that indexed sets vs gets can be resolved
            IndexResolver resolveIndex(*parseTree);
            OperatorResolver resolveOperator(*parseTree);

            for (auto& function : parseTree->functions()) {
                resolveIndex.visit(function);
                resolveOperator.visit(function);
            }
            for (auto& st : parseTree->structs()) {
                if (!st->isGeneric()) {
                    resolveIndex.visit(st);
                    resolveOperator.visit(st);
                }
            }
        }
    };
} // namespace pepper::ast
