
#pragma once

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
      public:
        struct Param {
            llvm::Type* Type;
            std::string Name;
            llvm::Value* Default;

            Param(std::string name, llvm::Type* type, llvm::Value* defaultValue = nullptr)
                : Name(std::move(name))
                , Type(type)
                , Default(defaultValue) {
            }
        };

        using Params = llvm::SmallVector<Param>;

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
    };

    class ExternFunction : public Function {
      public:
        using Function::Function;
    };

    class UserFunction : public Function {
      public:
        llvm::BasicBlock* Body = nullptr;
        Ref<llvm::IRBuilderBase> Builder = nullptr;
        unsigned int NumLocals = 0;

        UserFunction(std::string name, llvm::Type* returnType, const Params& params);
    };

} // namespace pepper
