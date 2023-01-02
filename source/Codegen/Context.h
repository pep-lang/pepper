
#pragma once

#include <memory>
#include <string>

#include "Codegen/Scope.h"
#include "Core/Common.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    namespace ast {
        class AST;
    }
    class Executor;
    class Function;
    class ModuleContext;
    class Types;
    class UserFunction;
    class Method;
    class Runtime;

    class Context {
        static Context* Instance;

        Ref<ModuleContext> Module;
        Ref<Types> TypeMap;
        Ref<Runtime> Builtins;
        Ref<Scope> Globals;
        Ref<Scope> Locals;

      public:
        static Context& get();
        static Ref<llvm::IRBuilderBase> ir();

        explicit Context(Ref<ModuleContext> module);
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

        [[nodiscard]] Ref<Runtime> runtime() const {
            return Builtins;
        }

        void pushFunction(Ref<UserFunction> function);
        void pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder = nullptr);
        void popScope();
    };

} // namespace pepper
