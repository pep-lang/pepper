
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "Frontend/Scope.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    class Types;
    class UserFunction;

    class PepContext {
        static PepContext* Instance;

        std::unique_ptr<llvm::LLVMContext> Context;
        Ref<Types> TypeMap;
        Ref<Scope> Globals;
        Ref<Scope> Locals;
        bool UnitTest = false;

      public:
        static PepContext& get();
        static Ref<llvm::IRBuilderBase> ir();

        explicit PepContext();
        ~PepContext();

        [[nodiscard]] Ref<Types> types() const {
            return TypeMap;
        }

        [[nodiscard]] Ref<Scope> globals() const {
            return Globals;
        }

        [[nodiscard]] Ref<Scope> locals() const {
            return Locals;
        }

        llvm::LLVMContext& getContext() {
            return *Context;
        }

        std::unique_ptr<llvm::LLVMContext>&& takeContext() {
            Locals.reset();
            Globals.reset();
            TypeMap.reset();
            Instance = nullptr;
            return std::move(Context);
        }

        void pushFunction(Ref<UserFunction> function);
        void pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder = nullptr);
        void popScope();
    };

} // namespace pepper
