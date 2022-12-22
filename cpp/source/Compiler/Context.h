
#pragma once

#include "Core/Common.h"
#include <cassert>
#include <memory>
#include <string>

namespace llvm {
    class LLVMContext;
    class Module;
    class IRBuilderBase;
} // namespace llvm

namespace pepper {
    namespace ast {
        class AST;
    }
    class Scope;
    class Executor;
    class Function;
    class Types;
    class UserFunction;

    class Context {
        static Context* Instance;

        Ref<Executor> Exec;
        std::unique_ptr<llvm::LLVMContext> Ctx;
        std::unique_ptr<llvm::Module> Module;
        Ref<Types> TypeMap;
        Ref<Scope> Builtins;
        Ref<Scope> Globals;
        Ref<Scope> Locals;
        Ref<ast::AST> Ast;

      public:
        static Context& get();

        explicit Context(const std::string& moduleName);
        ~Context();

        [[nodiscard]] llvm::Module* module() const;
        [[nodiscard]] llvm::LLVMContext& llvmContext() const;

        std::unique_ptr<llvm::Module>&& takeModule() {
            return std::move(Module);
        }

        std::unique_ptr<llvm::LLVMContext>&& takeContext() {
            return std::move(Ctx);
        }

        [[nodiscard]] Ref<Executor> executor() const {
            return Exec;
        }

        [[nodiscard]] Ref<Types> types() const {
            return TypeMap;
        }

        [[nodiscard]] Ref<Scope> globals() const {
            return Globals;
        }

        [[nodiscard]] Ref<Scope> locals() const {
            return Locals;
        }

        [[nodiscard]] Ref<ast::AST> ast() const {
            return Ast;
        }

        [[nodiscard]] Ref<Scope> runtime() const {
            return Builtins;
        }

        void pushFunction(Ref<UserFunction> function);
        void pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder = nullptr);
        void popScope();
    };

} // namespace pepper
