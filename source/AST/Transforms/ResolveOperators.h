#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/TypeSwitch.h"
#include "Specialization.h"
#include "Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveOperators : public Transformer {
        DECLARE_RTTI(ResolveOperators, Transformer);

        struct Resolver : public Visitor {
            SymbolTable Symbols;

            Resolver(const SymbolTable& symbols)
                : Symbols(symbols) {}

            void visitNode(NodeRef& node) {
                TypeSwitch<Node*, void>(node)
                    .Case<BinaryOp>([&](auto) { resolveBinaryOp(node); })
                    .Case<UnaryOp>([&](auto) { resolveUnaryOp(node); })
                    .Case<Index>([&](auto) { resolveIndex(node); });
            }

            void resolveBinaryOp(NodeRef& binOp) {
                if (auto assign = binOp->as<Assign>()) {
                    auto lhs = assign->LHS;
                    if (auto indexSet = lhs->as<Index>()) {
                        auto container = indexSet->LHS;
                        auto st = Symbols.Structs.lookup(container->type().toString());
                        if (st) {
                            // replace x[y] = z with x.__index_set(y, z)
                            binOp = new MethodCall(container, "__index_set", {indexSet->IndexExpr, assign->RHS});
                        }
                        // if the LHS indexed type isn't a struct, then this must be an indexed access or POD type
                        // and resolveIndex will fix it up
                    }
                }
            }

            void resolveUnaryOp(NodeRef& unOp) {}

            void resolveIndex(NodeRef& idxOp) {
                auto op = idxOp->as<Index>();
                auto lhs = op->LHS;
                auto st = Symbols.Structs.lookup(lhs->type().toString());
                if (st) {
                    if (auto method = st->getMethod("__index_get")) {
                        // Replace the idx op with a call to the index method
                        idxOp = new MethodCall(lhs, "__index_get", {op->IndexExpr});
                        return;
                    }
                    throw CompileError(idxOp->Source, "No index operator `[]` found for type {0}", st->Name);
                }
                idxOp = new ArrayIndex(lhs->type(), {lhs, op->IndexExpr});
            }
        };

        void run(Ref<AST> parseTree) override {
            Resolver resolver(*parseTree);

            Vector<FunctionDef*> allFunctions;
            for (const auto& function : parseTree->functions())
                allFunctions.emplace_back(function);
            for (const auto& st : parseTree->structs()) {
                if (!st->isGeneric())
                    allFunctions.append(Query(st->Methods).select<FunctionDef*>());
            }

            for (auto& func : allFunctions) {
                resolver.visit(func);
            }
        }
    };
} // namespace pepper::ast
