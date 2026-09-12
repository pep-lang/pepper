
#pragma once

#include <memory>
#include <string>
#include <utility>

#include "CodeGen/LLVM/Address.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"
#include "Param.h"
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
        const Ident identifier;
        Ref<Type> ret_type;
        const Params parameters;
        bool is_vararg;
        llvm::Function* llvm_function;
        Ref<Type> func_type;
        LinkageType linkage = LinkageType::ExternalLinkage;

      public:
        Function(llvm::Module& module,
                 const Ident& name,
                 Ref<Type> return_type,
                 const Params& params = Params(),
                 bool vararg = false,
                 LinkageType linkage = LinkageType::ExternalLinkage);

        const Ident& name() const {
            return identifier;
        }

        const Ref<Type> return_type() const {
            return ret_type;
        }

        const Vector<Param>& params() const {
            return parameters;
        }

        Ref<Function> ref() {
            return shared_from_this();
        }

        llvm::Function* function() const {
            return llvm_function;
        }

        Ref<Type> type() const {
            return func_type;
        }

        Address call(const Vector<Address>& args) const;
    };

    class UserFunction : public Function {
        DECLARE_RTTI(UserFunction, Function);

      public:
        llvm::BasicBlock* body = nullptr;
        llvm::BasicBlock* return_expr = nullptr;
        Address return_value;
        Ref<llvm::IRBuilderBase> ir_builder = nullptr;

        UserFunction(llvm::Module& module, const Ident& name, Ref<Type> return_type, const Params& params = Params());

        virtual bool count_arg_refs() const;

        llvm::BasicBlock* append_block(const Ident& name = {});
    };

    class Struct;

    class Method : public UserFunction {
        DECLARE_RTTI(Method, UserFunction);

        Ref<Struct> This;

      public:
        Method(llvm::Module& module, Ref<Struct> st, const Ident& name, Ref<Type> return_type, const Params& params = {})
            : UserFunction(module, name, return_type, params)
            , This(st) {}

        bool count_arg_refs() const override;
    };

} // namespace pepper
