
#pragma once

#include <memory>
#include <string>
#include <utility>

#include "CodeGen/Address.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"
#include "Frontend/Param.h"
#include "llvm/IR/Function.h"

namespace llvm {
    class BasicBlock;
    class Function;
    class IRBuilderBase;
    class Type;
} // namespace llvm

namespace pepper {
    class Function : public std::enable_shared_from_this<Function> {
        DECLARE_RTTI(Function);

      public:
        using LinkageType = llvm::GlobalValue::LinkageTypes;

      protected:
        const Ident Name;
        Ref<Type> ReturnType;
        const Params Parameters;
        bool Vararg;
        llvm::Function* Func;
        Ref<Type> FuncType;
        LinkageType Linkage = LinkageType::ExternalLinkage;

      public:
        Function(llvm::Module& module,
                 const Ident& name,
                 Ref<Type> returnType,
                 const Params& params = Params(),
                 bool vararg = false,
                 LinkageType linkage = LinkageType::ExternalLinkage);

        const Ident& name() const {
            return Name;
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

        Ref<Type> type() const {
            return FuncType;
        }

        Address call(const Vector<Address>& args) const;
    };

    class UserFunction : public Function {
        DECLARE_RTTI(UserFunction, Function);

      public:
        llvm::BasicBlock* Body = nullptr;
        llvm::BasicBlock* Return = nullptr;
        Address ReturnValue;
        Ref<llvm::IRBuilderBase> Builder = nullptr;

        UserFunction(llvm::Module& module, const Ident& name, Ref<Type> returnType, const Params& params = Params());

        virtual bool countArgRefs() const;

        llvm::BasicBlock* appendBlock(const Ident& name = {});
    };

    class Struct;

    class Method : public UserFunction {
        DECLARE_RTTI(Method, UserFunction);

        Ref<Struct> This;

      public:
        Method(llvm::Module& module, Ref<Struct> st, const Ident& name, Ref<Type> returnType, const Params& params = {})
            : UserFunction(module, name, returnType, params)
            , This(st) {}

        bool countArgRefs() const override;
    };

} // namespace pepper
