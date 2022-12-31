
#pragma once

#include <memory>
#include <string>
#include <utility>

#include "Codegen/IR/Value.h"
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
        Ref<TypeInfo> ReturnType;
        const Params Parameters;
        llvm::Function* Func;
        Ref<TypeInfo> FuncType;

      public:
        Function(const Name& name, Ref<TypeInfo> returnType, const Params& params = Params());

        const Name& name() const {
            return Identifier;
        }

        const Ref<TypeInfo> returnType() const {
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

        Ref<TypeInfo> type() const {
            return FuncType;
        }

        Value call(const Vector<Value>& args) const;
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

        UserFunction(const Name& name, Ref<TypeInfo> returnType, const Params& params = Params());
    };

    class Struct;

    class Method : public UserFunction {
        DECLARE_RTTI(Method, UserFunction);

        Ref<Struct> This;

      public:
        Method(Ref<Struct> st, const Name& name, Ref<TypeInfo> returnType, const Params& params = {})
            : UserFunction(name, returnType, params)
            , This(st) {
        }
    };

} // namespace pepper
