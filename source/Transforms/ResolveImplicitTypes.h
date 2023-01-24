#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveImplicitTypes : public Transformer {
        DECLARE_RTTI(ResolveImplicitTypes, Transformer);

        struct TypeReplacer : Visitor {
            llvm::StringMap<StructDef*> Structs;

            struct Scope {
                Ident Name;
                llvm::StringMap<Symbol*> Symbols;

                Scope(const Ident& name)
                    : Name(name) {}
            };

            Vector<Scope> Stack;

            TypeReplacer(llvm::StringMap<StructDef*>&& structs)
                : Structs(std::move(structs)) {
                Stack.emplace_back("Globals");
            }

            void pushScope(const Ident& name) {
                Stack.emplace_back(name);
            }

            void popScope() {
                Stack.pop_back();
            }

            Scope& locals() {
                return Stack.back();
            }

            Symbol* findSymbol(const Ident& name) const {
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (auto sym = scope.Symbols.lookup(name))
                        return sym;
                }
                return nullptr;
            }

            StructDef* findStruct(const Ident& name) const {
                return Structs.lookup(name);
            }

            TypeName typeOfExpr(Expression* expr) const {
                if (expr->type() != TypeName::Auto) {
                    return expr->type();
                }
                if (expr->is<SymbolRef>()) {
                    auto var = expr->as<SymbolRef>();
                    auto symbol = findSymbol(var->Name);
                    if (!symbol) {
                        throw CompileError(expr->Source, "Unknown symbol referenced: {0}", var->Name);
                    }
                    return symbol->Type;
                }
                if (expr->is<MemberRef>()) {
                    auto ref = expr->as<MemberRef>();
                    return typeOfExpr(ref->LHS);
                }
                throw CompileError(expr->Source, "Unknown expression type in {0}", expr->rtti()->name());
            }

            void enterNode(NodeRef& node) override {
                if (auto function = node->as<FunctionDef>())
                    pushScope(function->Name);
                if (auto block = node->as<Block>())
                    pushScope("block");
                if (auto st = node->as<StructDef>())
                    pushScope(st->Name);
            }

            void exitNode(NodeRef& node) override {
                if (node->is<FunctionDef>() || node->is<Block>() || node->is<StructDef>())
                    popScope();
            }

            void visitNode(NodeRef& node) override {
                if (auto sym = node->as<Symbol>()) {
                    locals().Symbols[sym->Name] = sym;
                }
                if (auto var = node->as<VariableDef>()) {
                    if (var->Type == TypeName::Auto) {
                        var->Type = typeOfExpr(var->Default);
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            llvm::StringMap<StructDef*> structs;
            for (auto& st : parseTree->structs()) {
                structs[st->Type.toString()] = st;
            }

            auto replacer = TypeReplacer(std::move(structs));
            for (auto& st : parseTree->structs()) {
                replacer.visit(st);
            }
            for (auto& fn : parseTree->functions()) {
                replacer.visit(fn);
            }
        }
    };
} // namespace pepper::ast
