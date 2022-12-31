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
            Ref<ast::FunctionDef> FunctionTarget;

            Ref<Node> Parent;
            Vector<Ref<Block>> BlockStack;
            Vector<Ref<Node>> LValueStack;
            Vector<Ref<Node>> RValueStack;

            Scope(const Name& name = "Anonymous")
                : Ident(name) {
            }
        };

        AST& ast;
        Vector<Ref<Scope>> ScopeStack;

      public:
        explicit BuilderImpl(AST& _ast)
            : ast(_ast) {
            ScopeStack.emplace_back(Ref<Scope>::New("Global")); // global scope
        }

        Ref<ast::FunctionDef> functionTarget() const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->FunctionTarget)
                    return scope->FunctionTarget;
            }
            return nullptr;
        }

        Ref<ast::StructDef> structTarget() const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->StructTarget)
                    return scope->StructTarget;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<StructDef> findStruct(const Name& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (auto str = scope->Structs.lookup(name))
                    return str;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::VariableDef> findVariable(const Name& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                auto var = scope->Locals.lookup(name);
                if (var) {
                    return var;
                }
            }
            if (auto st = structTarget()) {
                auto field = Query(st->Fields).find([&](auto f) { return f->identifier() == name; });
                if (field) {
                    return field.value();
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::FunctionDef> findFunction(const Name& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (auto var = scope->Functions.lookup(name)) {
                    return var;
                }
            }
            if (auto st = structTarget()) {
                auto method = Query(st->Methods).find([&](auto m) { return m->identifier() == name; });
                if (method) {
                    return method.value();
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
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->FunctionTarget) {
                    return scope->FunctionTarget;
                }
            }
            return nullptr;
        }

        void pushRValue(Ref<Node> value) override {
            auto& scope = ScopeStack.back();
            //            std::cout << "rpush: " << scope->Ident << ": " << value->toString() << std::endl;
            scope->RValueStack.push_back(value);
        }

        Ref<Node> popRValue() override {
            auto& scope = ScopeStack.back();
            if (scope->RValueStack.empty()) {
                throw InternalCompilerError("Attempted to pop empty r-value stack");
            }
            auto val = scope->RValueStack.pop_back_val();
            //            std::cout << "rpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Ref<Node> peekRValue(unsigned int idx = 0) const override {
            const auto& scope = ScopeStack.back();
            const int maxDepth = scope->RValueStack.size() - 1;
            if (idx > maxDepth) {
                return nullptr;
            }
            auto val = scope->RValueStack[maxDepth - idx];
            //            std::cout << "rpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        void pushLValue(Ref<Node> value) override {
            auto& scope = ScopeStack.back();
            //            std::cout << "lpush: " << scope->Ident << ": " << value->toString() << std::endl;
            scope->LValueStack.push_back(value);
        }

        Ref<Node> popLValue() override {
            auto& scope = ScopeStack.back();
            if (scope->LValueStack.empty()) {
                throw InternalCompilerError("Attempted to pop empty l-value stack");
            }
            auto val = scope->LValueStack.pop_back_val();
            //            std::cout << "lpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Ref<Node> peekLValue(unsigned int idx = 0) const override {
            const auto& scope = ScopeStack.back();
            const int maxDepth = scope->LValueStack.size() - 1;
            if (int(idx) > maxDepth) {
                return nullptr;
            }
            auto val = scope->LValueStack[maxDepth - idx];
            //            std::cout << "lpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        Builder* beginStruct(Ref<StructDef> structDef) override {
            auto& scope = ScopeStack.back();
            scope->Structs[structDef->identifier()] = structDef;
            scope->Functions[structDef->identifier()] = structDef->NewInstance;

            beginScope(structDef->identifier());
            auto& structScope = ScopeStack.back();
            structScope->StructTarget = structDef;
            return this;
        }

        Builder* endStruct() override {
            auto& scope = ScopeStack.back();
            auto& structDef = scope->StructTarget;
            structDef->Fields.append(scope->OrderedSymbols.begin(), scope->OrderedSymbols.end());
            structDef->finish();
            ast.newRoot(structDef);
            endScope();
            return this;
        }

        void beginExtension(Ref<StructDef> structDef) override {
            beginScope(structDef->identifier());
            auto& structScope = ScopeStack.back();
            structScope->StructTarget = structDef;
        }

        void endExtension() override {
            endScope();
        }

        Builder* beginFunction(Ref<ast::FunctionDef> func) override {
            auto& scope = ScopeStack.back();
            scope->Functions[func->identifier()] = func;
            // set the parent to the enclosing function for lambdas, its null otherwise
            func->body() = Ref<Block>::New(functionTarget(), func->identifier());
            beginBlock(func->body());
            auto& fnScope = ScopeStack.back();
            fnScope->FunctionTarget = func;
            fnScope->StructTarget = func->is<MethodDef>() ? func.as<MethodDef>()->structDef() : nullptr;
            return this;
        }

        Builder* endFunction() override {
            auto& scope = ScopeStack.back();
            auto& function = scope->FunctionTarget;
            endBlock();
            if (!structTarget()) {
                ast.newRoot(function);
            }
            return this;
        }

        void beginBlock(Ref<Block> block) override {
            beginScope(block->name());
            auto scope = ScopeStack.back();
            scope->BlockStack.push_back(block);
        }

        void endBlock() override {
            auto scope = ScopeStack.back();
            scope->BlockStack.pop_back();
            endScope();
        }

        Ref<Block> block() const override {
            const auto& scope = ScopeStack.back();
            if (scope->BlockStack.size())
                return ScopeStack.back()->BlockStack.back();
            return nullptr;
        }

        Builder* beginScope(const Name& name = "Anonymous") override {
            auto top = ScopeStack.back();
            std::string newScopeName = llvm::formatv("{0}.{1}", top->Ident, name);
            ScopeStack.emplace_back(Ref<Scope>::New(newScopeName));
            // std::cout << "begin: " << name << std::endl;
            return this;
        }

        Builder* endScope() override {
            auto scope = ScopeStack.pop_back_val();
            // std::cout << "end:   " << scope->Ident << std::endl;
            return this;
        }

        Builder* symbol(Ref<ast::VariableDef> var) override {
            auto& scope = ScopeStack.back();
            scope->Locals[var->identifier()] = var;
            scope->OrderedSymbols.push_back(var);
            if (block()) {
                block()->Items.push_back(var);
            }
            trace(var);
            return this;
        }

        Builder* insert(Ref<ast::Node> expr) override {
            // If there's an l-value waiting for an expression value, it'll pull it
            // off the stack when its terminal completes
            if (peekLValue()) {
                pushRValue(expr.as<Expression>());
            } else {
                block()->Items.push_back(expr);
            }

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
