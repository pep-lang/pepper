//
// Created by Justin Boswell on 12/21/22.
//

#include <utility>

#include "AST/AST.h"
#include "AST/Builder.h"
#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Vector.h"
#include "llvm/ADT/STLExtras.h"

namespace pepper::ast {
    class BuilderImpl : public Builder {
        struct Scope {
            const Ident Name;

            Resolvable<StructDef> StructTarget;
            ExtensionDef* ExtensionTarget = nullptr;
            FunctionDef* FunctionTarget = nullptr;

            Node* Parent = nullptr;
            Block* Block = nullptr;
            Vector<Node*> LValueStack;
            Vector<Node*> RValueStack;

            explicit Scope(Ident name = "Anonymous")
                : Name(std::move(name)) {}
        };

        AST& ast;
        Vector<Ref<Scope>> ScopeStack;

      public:
        explicit BuilderImpl(AST& _ast)
            : ast(_ast) {
            auto globals = Ref<Scope>::New("Global");
            ScopeStack.emplace_back(globals); // global scope
        }

        [[nodiscard]] FunctionDef* functionTarget() const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->FunctionTarget)
                    return scope->FunctionTarget;
            }
            return nullptr;
        }

        [[nodiscard]] Resolvable<StructDef> structTarget() const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->StructTarget)
                    return scope->StructTarget;
            }
            return {};
        }

        ExtensionDef* extensionTarget() const override {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->ExtensionTarget)
                    return scope->ExtensionTarget;
            }
            return nullptr;
        }

        FunctionDef* functionTarget() {
            for (const auto& scope : llvm::reverse(ScopeStack)) {
                if (scope->FunctionTarget) {
                    return scope->FunctionTarget;
                }
            }
            return nullptr;
        }

        void pushRValue(Node* value) override {
            auto& scope = ScopeStack.back();
            //            std::cout << "rpush: " << scope->Ident << ": " << value->toString() << std::endl;
            scope->RValueStack.push_back(value);
        }

        Node* popRValue() override {
            auto& scope = ScopeStack.back();
            if (scope->RValueStack.empty()) {
                Messages::Report<Warning>(Source, "Attempted to pop empty r-value stack");
                return nullptr;
            }
            auto val = scope->RValueStack.pop_back_val();
            //            std::cout << "rpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Node* peekRValue(unsigned int idx = 0) const override {
            const auto& scope = ScopeStack.back();
            const int maxDepth = (int)scope->RValueStack.size() - 1;
            if (idx > maxDepth) {
                return nullptr;
            }
            auto val = scope->RValueStack[maxDepth - idx];
            //            std::cout << "rpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        void pushLValue(Node* value) override {
            auto& scope = ScopeStack.back();
            //            std::cout << "lpush: " << scope->Ident << ": " << value->toString() << std::endl;
            scope->LValueStack.push_back(value);
        }

        Node* popLValue() override {
            auto& scope = ScopeStack.back();
            if (scope->LValueStack.empty()) {
                throw InternalCompilerError(Source, "Attempted to pop empty l-value stack");
            }
            auto val = scope->LValueStack.pop_back_val();
            //            std::cout << "lpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Node* peekLValue(unsigned int idx = 0) const override {
            const auto& scope = ScopeStack.back();
            const int maxDepth = (int)scope->LValueStack.size() - 1;
            if (int(idx) > maxDepth) {
                return nullptr;
            }
            auto val = scope->LValueStack[maxDepth - idx];
            //            std::cout << "lpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        void beginStruct(StructDef* structDef) override {
            auto& scope = ScopeStack.back();
            structDef->Source = Source;
            beginScope(structDef->Name);
            auto& structScope = ScopeStack.back();
            structScope->StructTarget = structDef;
        }

        void endStruct() override {
            auto& scope = ScopeStack.back();
            auto& structDef = scope->StructTarget;
            structDef->finish();
            ast.insert(structDef.value());
            endScope();
        }

        void beginExtension(ExtensionDef* ext) override {
            beginScope(ext->Target.toString());
            auto& extScope = ScopeStack.back();
            extScope->ExtensionTarget = ext;
        }

        void endExtension() override {
            auto& scope = ScopeStack.back();
            auto extension = scope->ExtensionTarget;
            ast.insert(extension);
            endScope();
        }

        void beginFunction(FunctionDef* func) override {
            auto& scope = ScopeStack.back();

            // set the parent to the enclosing function for lambdas, its null otherwise
            func->Source = Source;
            func->Body->Source = func->Source;
            beginScope(func->Type.toString());
            auto& fnScope = ScopeStack.back();
            fnScope->Block = func->Body;
            fnScope->FunctionTarget = func;
            fnScope->StructTarget = func->is<MethodDef>() ? func->as<MethodDef>()->Struct : Resolvable<StructDef>{};
        }

        void endFunction() override {
            auto& scope = ScopeStack.back();
            auto function = scope->FunctionTarget;
            endScope();
            if (!structTarget() && !extensionTarget()) {
                ast.insert(function);
            }
        }

        void beginBlock(Block* block) override {
            beginScope(block->Name);
            auto scope = ScopeStack.back();
            scope->Block = block;
        }

        void endBlock() override {
            endScope();
        }

        Block* block() const override {
            const auto& scope = ScopeStack.back();
            return scope->Block;
        }

        void beginScope(const Ident& name = "Anonymous") override {
            auto top = ScopeStack.back();
            const std::string newScopeName = llvm::formatv("{0}.{1}", top->Name, name);
            ScopeStack.emplace_back(Ref<Scope>::New(newScopeName));
            PEP_TRACE(TraceChannel::Parser, "Scope({0}) {{", name);
            Messages::Indent(TraceChannel::Parser);
        }

        void endScope() override {
            auto scope = ScopeStack.pop_back_val();
            Messages::Outdent(TraceChannel::Parser);
            PEP_TRACE(TraceChannel::Parser, "} // end Scope({0})", scope->Name);
        }

        void symbol(VariableDef* var) override {
            auto& scope = ScopeStack.back();
            if (var->is<FieldDef>()) {
                auto field = var->as<FieldDef>();
                structTarget().value()->Fields.push_back(field);
            } else {
                if (block()) {
                    block()->Items.push_back(var);
                }
            }
            trace(var);
        }

        void insert(Node* expr) override {
            // If there's an l-value waiting for an expression value, it'll pull it
            // off the stack when its terminal completes
            if (peekLValue()) {
                pushRValue(expr->as<Expression>());
            } else {
                block()->Items.push_back(expr);
                trace(expr);
            }
        }

        void import(Import* import) override {
            ast.insert(import);
            trace(import);
        }

        void trace(const Node* node) const override {
            PEP_TRACE(TraceChannel::Parser, node->toString());
        }
    };

    Builder* AST::builder() {
        if (!TreeBuilder) {
            TreeBuilder = std::make_unique<BuilderImpl>(*this);
        }

        return TreeBuilder.get();
    }
} // namespace pepper::ast
