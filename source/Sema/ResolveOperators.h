#pragma once

#include <llvm/Support/Format.h>

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ResolveOperators : Transformer {
        DECLARE_RTTI(ResolveOperators, Transformer);

        struct IndexResolver : Visitor {
            SymbolTable symbols;

            IndexResolver(const SymbolTable& symbols)
                : symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*>(node)
                    .Case<BinaryOp>([&](auto) { resolve_binary_op(node); })
                    .Case<UnaryOp>([&](auto) { resolve_unary_op(node); })
                    .Case<Index>([&](auto) { resolve_index(node); });
            }

            void resolve_binary_op(NodeRef& binOp) {
                auto op = binOp->as<BinaryOp>();
                auto lhs = op->lhs;
                // If the lhs is not a struct, it can't be overloaded
                if (!lhs->type().is_struct()) {
                    return;
                }

                // Special case assign to index operations -> __index_set
                if (auto assign = op->as<Assign>()) {
                    if (auto indexSet = lhs->as<Index>()) {
                        auto container = indexSet->lhs;
                        auto st = symbols.structs.lookup(container->type().to_string());
                        if (st) {
                            // replace x[y] += z with :
                            // tmp = x.__index_get(y)
                            // x.__index_set(y, tmp += z)
                            Node::push_source(binOp->source_loc);
                            auto get = new MethodCall(container, {"__index_get"}, {indexSet->expr});
                            auto tmpName =
                                llvm::formatv("_tmp_{0}_{1}", binOp->source_loc.line, binOp->source_loc.column).str();
                            auto tmp = new VariableDef(get->type(), tmpName, get);
                            binOp = tmp;
                            auto tmpRef = new SymbolRef(tmpName);
                            assign->lhs = tmpRef;
                            auto set = new MethodCall(container, {"__index_set"}, {indexSet->expr, assign});
                            block()->items.insert_after(binOp, set);
                            Node::pop_source();
                        }
                        // if the lhs indexed type isn't a struct, then this must be an indexed access or POD type
                        // and resolve_index will fix it up
                    }
                }
            }

            void resolve_unary_op(NodeRef& unOp) {
                // TODO
            }

            void resolve_index(NodeRef& idxOp) {
                auto op = idxOp->as<Index>();
                auto lhs = op->lhs;
                auto st = symbols.structs.lookup(lhs->type().to_string());
                if (st) {
                    if (st->get_method("__index_get")) {
                        // Replace the idx op with a call to the index method
                        Node::push_source(idxOp->source_loc);
                        idxOp = new MethodCall(lhs, {"__index_get"}, {op->expr});
                        Node::pop_source();
                        return;
                    }
                    throw CompileError(idxOp->source_loc, "No index operator `[]` found for type {0}", st->name);
                }
                // must be a POD type array, use the default indexing
                idxOp = new ArrayIndex(lhs->type(), {lhs, op->expr});
            }
        };

        struct OperatorResolver : public Visitor {
            SymbolTable symbols;

            OperatorResolver(const SymbolTable& symbols)
                : symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*, void>(node)
                    .Case<BinaryOp>([&](auto) { resolve_binary_op(node); })
                    .Case<UnaryOp>([&](auto) { resolve_unary_op(node); });
            }

            void resolve_binary_op(NodeRef& binOp) {
                auto op = binOp->as<BinaryOp>();
                auto lhs = op->lhs;
                // If the lhs is not a struct, it can't be overloaded
                if (!lhs->type().is_struct()) {
                    return;
                }

                // Resolve any overloads on lhs
                auto opName = op->opName();
                if (!opName.empty()) {
                    auto st = symbols.structs.lookup(lhs->type().to_string());
                    if (st) {
                        binOp = new MethodCall(lhs, {opName}, {op->rhs});
                    }
                }
            }

            void resolve_unary_op(NodeRef& unOp) {
                // TODO
            }
        };

        void run(Ref<Module> module) override {
            // Index operations need to be resolved first so that indexed sets vs gets can be resolved
            IndexResolver index_resolver(*module);
            OperatorResolver operator_resolver(*module);

            for (auto& function : module->functions()) {
                index_resolver.visit(function);
                operator_resolver.visit(function);
            }
            for (auto& st : module->structs()) {
                if (!st->is_generic()) {
                    index_resolver.visit(st);
                    operator_resolver.visit(st);
                }
            }
        }
    };
} // namespace pepper::sema
