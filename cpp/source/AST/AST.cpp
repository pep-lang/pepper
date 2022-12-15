
#include "AST/AST.h"

#include "AST/Nodes.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Type.h"
#include "Compiler/Value.h"
#include "llvm/ADT/STLExtras.h"
#include <vector>

namespace pepper {
    class BuilderImpl : public AST::Builder {
        struct Scope {
            llvm::StringMap<Ref<Type>> Types;
            llvm::StringMap<Ref<ast::VariableDef>> Locals;
            llvm::StringMap<Ref<ast::FunctionDef>> Functions;
            std::vector<Ref<ast::Node>> Stack;
            Ref<ast::FunctionDef> ReturnTarget = nullptr;
        };

        AST& ast;
        std::vector<Scope> Stack;

      public:
        BuilderImpl(AST& _ast)
            : ast(_ast) {
            Stack.emplace_back(Scope()); // global scope
        }

        Ref<ast::VariableDef> findVariable(const std::string& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                auto var = scope.Locals.lookup(name);
                if (var) {
                    return var;
                }
            }
            return nullptr;
        }

        Ref<ast::FunctionDef> findFunction(const std::string& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (auto var = scope.Functions.lookup(name)) {
                    return var;
                }
            }
            return nullptr;
        }

        Ref<ast::Symbol> findSymbol(const std::string& name) const override {
            if (auto var = findVariable(name)) {
                return var.as<ast::Symbol>();
            }
            if (auto func = findFunction(name)) {
                return func.as<ast::Symbol>();
            }
            return nullptr;
        }

        Ref<Type> findType(const std::string& name) const override {
            for (const auto& scope : llvm::reverse(Stack)) {
                if (auto ty = scope.Types.lookup(name)) {
                    return ty;
                }
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

        virtual void pushStack(Ref<ast::Node> value) override {
            auto& scope = Stack.back();
            scope.Stack.push_back(value);
        }

        virtual Ref<ast::Node> popStack() override {
            auto& scope = Stack.back();
            if (scope.Stack.empty()) {
                throw new InternalCompilerError("Attempted to pop empty AST stack");
            }
            auto val = scope.Stack.back();
            scope.Stack.pop_back();
            return val;
        }

        virtual Ref<ast::Node> peekStack(unsigned int idx) override {
            const auto& scope = Stack.back();
            if (idx > (scope.Stack.size() - 1)) {
                throw new InternalCompilerError("Attempted to peek AST stack slot {}, stack size: {}",
                                                idx,
                                                scope.Stack.size());
            }
            return scope.Stack[scope.Stack.size() - 1 - idx];
        }

        Builder* beginFunction(Ref<ast::FunctionDef> func) override {
            auto& scope = Stack.back();
            scope.Functions[func->name()] = func;
            scope.ReturnTarget = func;
            beginScope();
            return this;
        }

        Builder* endFunction() override {
            endScope();
            return this;
        }

        Builder* beginScope() override {
            Stack.emplace_back(Scope());
            return this;
        }

        Builder* endScope() override {
            Stack.pop_back();
            return this;
        }

        Builder* type(Ref<Type> newType) override {
            auto& scope = Stack.back();
            scope.Types[newType->name()] = newType;
            return this;
        }

        Builder* variable(Ref<ast::VariableDef> var) override {
            auto& scope = Stack.back();
            scope.Locals[var->name()] = var;
            return this;
        }

        Builder* expression(Ref<ast::Expression> expr) override {
            return this;
        }
    };

    AST::AST() {
    }

    Ref<AST::Builder> AST::builder() {
        if (auto active = ActiveBuilder.lock()) {
            return active;
        }

        auto active = Ref<BuilderImpl>::create(*this);
        ActiveBuilder = active;
        return active.as<AST::Builder>();
    }

} // namespace pepper
