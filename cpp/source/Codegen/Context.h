
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"

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
    class ModuleContext;
    class Types;
    class UserFunction;

    class Context {
        static Context* Instance;

        Ref<ModuleContext> Module;
        Ref<Types> TypeMap;
        Ref<Scope> Builtins;
        Ref<Scope> Globals;
        Ref<Scope> Locals;

      public:
        static Context& get();
        static Ref<llvm::IRBuilderBase> ir();
        static Ref<llvm::IRBuilderBase> registers();

        explicit Context(const std::string& moduleName);
        ~Context();

        [[nodiscard]] llvm::Module* module() const;
        [[nodiscard]] llvm::LLVMContext& llvmContext() const;

        Ref<ModuleContext> moduleContext() const {
            return Module;
        }

        std::unique_ptr<llvm::Module>&& takeModule();
        std::unique_ptr<llvm::LLVMContext>&& takeContext();

        [[nodiscard]] Ref<Types> types() const {
            return TypeMap;
        }

        [[nodiscard]] Ref<Scope> globals() const {
            return Globals;
        }

        [[nodiscard]] Ref<Scope> locals() const {
            return Locals;
        }

        [[nodiscard]] Ref<Scope> runtime() const {
            return Builtins;
        }

        void pushFunction(Ref<UserFunction> function);
        void pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder = nullptr);
        void popScope();
    };

} // namespace pepper
