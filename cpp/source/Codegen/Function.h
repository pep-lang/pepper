
#pragma once

#include "Compiler/Param.h"
#include "Core/Common.h"
#include "llvm/ADT/SmallVector.h"
#include <memory>
#include <string>
#include <utility>

namespace llvm {
    class BasicBlock;
    class Function;
    class FunctionType;
    class IRBuilderBase;
    class Type;
    class Value;
} // namespace llvm

namespace pepper {
    class Function : public std::enable_shared_from_this<Function> {
        DECLARE_RTTI(Function);

      protected:
        const std::string Name;
        llvm::Type* ReturnType;
        const Params Parameters;
        llvm::Function* Func;
        llvm::FunctionType* FuncType;

      public:
        Function(std::string name, llvm::Type* returnType, const Params& params);

        const std::string& name() const {
            return Name;
        }

        const llvm::Type* returnType() const {
            return ReturnType;
        }

        const llvm::SmallVector<Param>& params() const {
            return Parameters;
        }

        Ref<Function> ref() {
            return shared_from_this();
        }

        llvm::Function* function() const {
            return Func;
        }

        llvm::FunctionType* type() const {
            return FuncType;
        }
    };

    class ExternFunction : public Function {
        DECLARE_RTTI(ExternFunction, Function);

      public:
        using Function::Function;
    };

    class UserFunction : public Function {
        DECLARE_RTTI(UserFunction, Function);

      public:
        llvm::BasicBlock* Body = nullptr;
        Ref<llvm::IRBuilderBase> Builder = nullptr;
        unsigned int NumLocals = 0;

        UserFunction(std::string name, llvm::Type* returnType, const Params& params);
    };

} // namespace pepper
