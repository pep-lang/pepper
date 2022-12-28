//
// Created by Justin Boswell on 12/21/22.
//

#include "AST/Builder.h"
#include <iostream>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Core/Vector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/Type.h"

namespace pepper::ast {
    class BuilderImpl : public Builder {
        struct Scope {
            Name Ident;

            llvm::StringMap<Ref<ast::VariableDef>> Locals;
            llvm::StringMap<Ref<Symbol>> Symbols;
            Vector<Ref<Symbol>> OrderedSymbols;

            llvm::StringMap<Ref<StructDef>> Structs;
            Ref<ast::StructDef> StructTarget;

            llvm::StringMap<Ref<ast::FunctionDef>> Functions;
            Vector<Ref<FunctionDef>> OrderedFunctions;
            Vector<Ref<Expression>> Expressions;
            Ref<ast::FunctionDef> FunctionTarget = nullptr;

            Ref<Node> Parent;
            Vector<Ref<Block>> BlockStack;
            Vector<Ref<Node>> LValueStack;
            Vector<Ref<Expression>> RValueStack;

            Scope(const Name& name = "Anonymous")
                : Ident(name) {
            }
        };

        AST& ast;
        Vector<Ref<Scope>> Stack;

      public:
        explicit BuilderImpl(AST& _ast)
            : ast(_ast) {
            Stack.emplace_back(Ref<Scope>::New("Global")); // global scope
        }

        Ref<ast::FunctionDef> functionTarget() const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (scope->FunctionTarget)
                    return scope->FunctionTarget;
            }
            return nullptr;
        }

        Ref<ast::StructDef> structTarget() const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (scope->StructTarget)
                    return scope->StructTarget;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<StructDef> findStruct(const Name& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (auto str = scope->Structs.lookup(name))
                    return str;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::VariableDef> findVariable(const Name& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                auto var = scope->Locals.lookup(name);
                if (var) {
                    return var;
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::FunctionDef> findFunction(const Name& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (auto var = scope->Functions.lookup(name)) {
                    return var;
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::Symbol> findSymbol(const Name& name) const override {
            if (auto var = findVariable(name)) {
                return var.as<ast::Symbol>();
            }
            if (auto func = findFunction(name)) {
                return func.as<ast::Symbol>();
            }
            return nullptr;
        }

        Ref<ast::FunctionDef> functionTarget() {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (scope->FunctionTarget) {
                    return scope->FunctionTarget;
                }
            }
            return nullptr;
        }

        void pushRValue(Ref<Expression> value) override {
            auto& scope = Stack.back();
            scope->RValueStack.push_back(value);
        }

        Ref<Expression> popRValue() override {
            auto& scope = Stack.back();
            if (scope->RValueStack.empty()) {
                throw InternalCompilerError("Attempted to pop empty AST stack");
            }
            auto val = scope->RValueStack.back();
            scope->RValueStack.pop_back();
            return val;
        }

        Ref<Expression> peekRValue(unsigned int idx = 0) const override {
            const auto& scope = Stack.back();
            if (idx > (scope->RValueStack.size() - 1)) {
                throw InternalCompilerError(
                    "Attempted to peek AST stack slot {}, stack size: {}", idx, scope->RValueStack.size());
            }
            return scope->RValueStack[scope->RValueStack.size() - 1 - idx];
        }

        void pushLValue(Ref<Node> value) override {
            auto& scope = Stack.back();
            scope->LValueStack.push_back(value);
        }

        Ref<Node> popLValue() override {
            auto& scope = Stack.back();
            if (scope->LValueStack.empty()) {
                throw InternalCompilerError("Attempted to pop empty AST stack");
            }
            auto val = scope->LValueStack.back();
            scope->LValueStack.pop_back();
            return val;
        }

        Ref<Node> peekLValue(unsigned int idx = 0) const override {
            const auto& scope = Stack.back();
            const int maxDepth = scope->LValueStack.size() - 1;
            if (int(idx) > maxDepth) {
                return nullptr;
            }
            return scope->LValueStack[maxDepth - idx];
        }

        Builder* beginStruct(Ref<StructDef> structDef) override {
            auto& scope = Stack.back();
            scope->Structs[structDef->identifier()] = structDef;
            scope->Functions[structDef->identifier()] = structDef->NewInstance;

            if (!structTarget() && !functionTarget()) {
                ast.newRoot(structDef);
            }

            beginScope(structDef->identifier());
            auto& structScope = Stack.back();
            structScope->StructTarget = structDef;
            return this;
        }

        Builder* endStruct() override {
            auto& scope = Stack.back();
            auto& structDef = scope->StructTarget;
            structDef->Fields.append(scope->OrderedSymbols.begin(), scope->OrderedSymbols.end());
            structDef->finish();
            endScope();
            return this;
        }

        Builder* beginFunction(Ref<ast::FunctionDef> func) override {
            auto& scope = Stack.back();
            scope->Functions[func->identifier()] = func;
            beginScope(func->identifier());
            auto& fnScope = Stack.back();
            fnScope->FunctionTarget = func;
            return this;
        }

        Builder* endFunction() override {
            auto& scope = Stack.back();
            auto& function = scope->FunctionTarget;
            std::for_each(scope->Locals.begin(), scope->Locals.end(), [&](auto& local) {
                auto var = local.second;
                function->locals().push_back(var);
            });
            ast.newRoot(function);
            endScope();
            return this;
        }

        void beginBlock(Ref<Block> block) override {
            beginScope(block->name());
            auto scope = Stack.back();
            scope->BlockStack.push_back(block);
        }

        void endBlock() override {
            endScope();
        }

        Ref<Block> block() const override {
            return Stack.back()->BlockStack.back();
        }

        Builder* beginScope(const Name& name = "Anonymous") override {
            Stack.emplace_back(Ref<Scope>::New(name));
            return this;
        }

        Builder* endScope() override {
            Stack.pop_back();
            return this;
        }

        Builder* symbol(Ref<ast::VariableDef> var) override {
            auto& scope = Stack.back();
            scope->Locals[var->identifier()] = var;
            scope->OrderedSymbols.push_back(var);
            return this;
        }

        Builder* expression(Ref<ast::Expression> expr) override {
            auto function = functionTarget();
            if (peekLValue())
                pushRValue(expr);
            else
                function->body().push_back(expr);

            return this;
        }

        void trace(const Ref<Node>& node) const override {
            PEP_TRACE(TraceChannel::Parser, node->toString());
        }
    };

    Ref<Builder> AST::builder() {
        if (auto active = ActiveBuilder.lock()) {
            return active;
        }

        auto active = Ref<BuilderImpl>::New(*this);
        ActiveBuilder = active;
        return active.as<Builder>();
    }
} // namespace pepper::ast
