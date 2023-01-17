
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "Frontend/Scope.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    namespace ast {
        class AST;
    }
    class Executor;
    class Function;
    class CodeGenModule;
    class Types;
    class UserFunction;
    class Method;
    class Runtime;

    class Context {
        static Context* Instance;

        Ref<CodeGenModule> Module;
        Ref<Types> TypeMap;
        Ref<Runtime> Builtins;
        Ref<Scope> Globals;
        Ref<Scope> Locals;

      public:
        static Context& get();
        static Ref<llvm::IRBuilderBase> ir();

        explicit Context(Ref<CodeGenModule> module);
        ~Context();

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
