//
// Created by Justin Boswell on 12/21/22.
//

#include "AST/Builder.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/Type.h"
#include <vector>

namespace pepper::ast {
    class BuilderImpl : public Builder {
        struct Scope {
            Name Ident;

            llvm::StringMap<Ref<ast::VariableDef>> Locals;
            llvm::StringMap<Ref<Symbol>> Symbols;
            std::vector<Ref<Symbol>> OrderedSymbols;

            llvm::StringMap<Ref<StructDef>> Structs;
            Ref<ast::StructDef> StructTarget;

            llvm::StringMap<Ref<ast::FunctionDef>> Functions;
            std::vector<Ref<FunctionDef>> OrderedFunctions;
            std::vector<Ref<Expression>> Expressions;
            Ref<ast::FunctionDef> ReturnTarget = nullptr;

            std::vector<Ref<ast::Node>> Stack;

            Scope(const Name& name = "Anonymous")
                : Ident(name) {
            }
        };

        AST& ast;
        std::vector<Scope> Stack;

      public:
        explicit BuilderImpl(AST& _ast)
            : ast(_ast) {
            Stack.emplace_back("Global"); // global scope
        }

        Ref<ast::FunctionDef> returnTarget() const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (scope.ReturnTarget)
                    return scope.ReturnTarget;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::VariableDef> findVariable(const Name& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                auto var = scope.Locals.lookup(name);
                if (var) {
                    return var;
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::FunctionDef> findFunction(const Name& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (auto var = scope.Functions.lookup(name)) {
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

        Ref<ast::FunctionDef> returnTarget() {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (scope.ReturnTarget) {
                    return scope.ReturnTarget;
                }
            }
            return nullptr;
        }

        void pushStack(Ref<ast::Node> value) override {
            auto& scope = Stack.back();
            scope.Stack.push_back(value);
        }

        Ref<ast::Node> popStack() override {
            auto& scope = Stack.back();
            if (scope.Stack.empty()) {
                throw InternalCompilerError("Attempted to pop empty AST stack");
            }
            auto val = scope.Stack.back();
            scope.Stack.pop_back();
            return val;
        }

        Ref<ast::Node> peekStack(unsigned int idx) override {
            const auto& scope = Stack.back();
            if (idx > (scope.Stack.size() - 1)) {
                throw InternalCompilerError(
                    "Attempted to peek AST stack slot {}, stack size: {}", idx, scope.Stack.size());
            }
            return scope.Stack[scope.Stack.size() - 1 - idx];
        }

        Builder* beginFunction(Ref<ast::FunctionDef> func) override {
            auto& scope = Stack.back();
            scope.Functions[func->identifier()] = func;
            beginScope(func->identifier());
            auto& fnScope = Stack.back();
            fnScope.ReturnTarget = func;
            return this;
        }

        Builder* endFunction() override {
            auto& scope = Stack.back();
            auto function = scope.ReturnTarget;
            std::for_each(scope.Locals.begin(), scope.Locals.end(), [&function](auto& local) {
                function->locals().push_back(local.second);
            });
            ast.newRoot(function);
            endScope();
            return this;
        }

        Builder* beginScope(const Name& name = "Anonymous") override {
            Stack.emplace_back(name);
            return this;
        }

        Builder* endScope() override {
            Stack.pop_back();
            return this;
        }

        Builder* variable(Ref<ast::VariableDef> var) override {
            auto& scope = Stack.back();
            scope.Locals[var->identifier()] = var;
            return this;
        }

        Builder* expression(Ref<ast::Expression> expr) override {
            auto function = returnTarget();
            function->body().push_back(expr);
            return this;
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
