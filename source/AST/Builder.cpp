//
// Created by Justin Boswell on 12/21/22.
//

#include "AST/Builder.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Core/Vector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::ast {
    class BuilderImpl : public Builder {
        struct Scope {
            const Ident Name;

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
            Ref<Block> Block;
            Vector<Ref<Node>> LValueStack;
            Vector<Ref<Node>> RValueStack;

            explicit Scope(const Ident& name = "Anonymous")
                : Name(name) {
            }
        };

        AST& ast;
        Vector<Ref<Scope>> ScopeStack;

      public:
        explicit BuilderImpl(AST& _ast)
            : ast(_ast) {
            ScopeStack.emplace_back(Ref<Scope>::New("Global")); // global scope
        }

        [[nodiscard]] Ref<ast::FunctionDef> functionTarget() const override {
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

        [[nodiscard]] Ref<StructDef> findStruct(const Ident& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (auto str = scope->Structs.lookup(name))
                    return str;
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::VariableDef> findVariable(const Ident& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                auto var = scope->Locals.lookup(name);
                if (var) {
                    return var;
                }
            }
            if (auto st = structTarget()) {
                auto field = Query(st->Fields).find([&](auto f) { return f->Name == name; });
                if (field) {
                    return field.value();
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::FunctionDef> findFunction(const Ident& name) const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (auto var = scope->Functions.lookup(name)) {
                    return var;
                }
            }
            if (auto st = structTarget()) {
                auto method = Query(st->Methods).find([&](auto m) { return m->Name == name; });
                if (method) {
                    return method.value();
                }
            }
            return nullptr;
        }

        [[nodiscard]] Ref<ast::Symbol> findSymbol(const Ident& name) const override {
            if (auto var = findVariable(name)) {
                return var.as<ast::Symbol>();
            }
            if (auto func = findFunction(name)) {
                return func.as<ast::Symbol>();
            }
            return nullptr;
        }

        Ref<StructDef> specialize(const TypeName& spec) override {
            auto specialized = StructDef::New(spec, spec.toString());
            specialized->specialize(findStruct(spec.Name), {spec.GenericArgs.begin(), spec.GenericArgs.end()});
            return specialized;
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
                Messages::Report<Warning>("Attempted to pop empty r-value stack");
                return nullptr;
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

        void beginStruct(Ref<StructDef> structDef) override {
            auto& scope = ScopeStack.back();
            scope->Structs[structDef->Name] = structDef;
            scope->Functions[structDef->Name] = structDef->NewInstance;

            beginScope(structDef->Name);
            auto& structScope = ScopeStack.back();
            structScope->StructTarget = structDef;
        }

        void endStruct() override {
            auto& scope = ScopeStack.back();
            auto& structDef = scope->StructTarget;
            structDef->finish();
            ast.newRoot(structDef);
            endScope();
        }

        void beginExtension(Ref<StructDef> structDef) override {
            beginScope(structDef->Name);
            auto& structScope = ScopeStack.back();
            structScope->StructTarget = structDef;
        }

        void endExtension() override {
            endScope();
        }

        void beginFunction(Ref<ast::FunctionDef> func) override {
            auto& scope = ScopeStack.back();
            scope->Functions[func->Name] = func;
            // set the parent to the enclosing function for lambdas, its null otherwise
            func->Body = Ref<Block>::New(functionTarget(), func->Name);
            beginBlock(func->Body);
            auto& fnScope = ScopeStack.back();
            fnScope->FunctionTarget = func;
            fnScope->StructTarget = func->is<MethodDef>() ? func.as<MethodDef>()->Struct : nullptr;
        }

        void endFunction() override {
            auto& scope = ScopeStack.back();
            auto function = scope->FunctionTarget;
            endBlock();
            if (!structTarget()) {
                ast.newRoot(function);
            }
        }

        void beginBlock(Ref<Block> block) override {
            beginScope(block->Name);
            auto scope = ScopeStack.back();
            scope->Block = block;
        }

        void endBlock() override {
            endScope();
        }

        Ref<Block> block() const override {
            const auto& scope = ScopeStack.back();
            return scope->Block;
        }

        void beginScope(const Ident& name = "Anonymous") override {
            auto top = ScopeStack.back();
            std::string newScopeName = llvm::formatv("{0}.{1}", top->Name, name);
            ScopeStack.emplace_back(Ref<Scope>::New(newScopeName));
            PEP_TRACE(TraceChannel::Parser, "Scope({0}) {{", name);
            Messages::Indent(TraceChannel::Parser);
            // std::cout << "begin: " << name << std::endl;
        }

        void endScope() override {
            auto scope = ScopeStack.pop_back_val();
            // std::cout << "end:   " << scope->Ident << std::endl;
            Messages::Outdent(TraceChannel::Parser);
            PEP_TRACE(TraceChannel::Parser, "}} // end Scope({0})", scope->Name);
        }

        void symbol(Ref<ast::VariableDef> var) override {
            auto& scope = ScopeStack.back();
            if (var->is<FieldDef>()) {
                auto field = var.as<FieldDef>();
                structTarget()->Fields.push_back(field);
            } else {
                scope->Locals[var->Name] = var;
                scope->OrderedSymbols.push_back(var);
                if (block()) {
                    block()->Items.push_back(var);
                }
            }
            trace(var);
        }

        void insert(Ref<ast::Node> expr) override {
            // If there's an l-value waiting for an expression value, it'll pull it
            // off the stack when its terminal completes
            if (peekLValue()) {
                pushRValue(expr.as<Expression>());
            } else {
                block()->Items.push_back(expr);
            }
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
