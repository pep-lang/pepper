
#pragma once

#include <memory>
#include <string>
#include <utility>

#include "Codegen/Param.h"
#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/Vector.h"

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
        const Name Identifier;
        Ref<Type> ReturnType;
        const Params Parameters;
        llvm::Function* Func;
        llvm::FunctionType* FuncType;

      public:
        Function(const Name& name, Ref<Type> returnType, const Params& params = Params());

        const Name& name() const {
            return Identifier;
        }

        const Ref<Type> returnType() const {
            return ReturnType;
        }

        const Vector<Param>& params() const {
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

        llvm::Value* call(const Vector<llvm::Value*>& args) const;
    };

    class ExternFunction : public Function {
        DECLARE_RTTI(ExternFunction, Function);

      public:
        using Function::Function;

        static void StaticInit();

      public:
        static Ref<ExternFunction> Malloc;
        static Ref<ExternFunction> Free;
    };

    class UserFunction : public Function {
        DECLARE_RTTI(UserFunction, Function);

      public:
        llvm::BasicBlock* Body = nullptr;
        Ref<llvm::IRBuilderBase> Builder = nullptr;
        unsigned int NumLocals = 0;

        UserFunction(const Name& name, Ref<Type> returnType, const Params& params = Params());
    };

    class Method : public UserFunction {
        DECLARE_RTTI(Method, UserFunction);

      public:
        using UserFunction::UserFunction;
    };

} // namespace pepper
