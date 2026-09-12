
#include "Function.h"

#include "Core/Exceptions.h"
#include "Operations.h"
#include "SemaContext.h"
#include "Struct.h"
#include "Types.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(llvm::Module& module,
                       const Ident& name,
                       Ref<Type> return_type,
                       const Params& params,
                       bool vararg,
                       LinkageType linkage)
        : identifier(name)
        , ret_type(return_type)
        , parameters(params)
        , is_vararg(vararg)
        , linkage(linkage) {
        Vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(*p.type); });
        auto llvmType = llvm::FunctionType::get(*return_type, paramTypes, false);
        auto sig = Types::to_string(llvmType);
        func_type = Types::add(Ref<Type>::create(sig, llvmType));
        llvm_function = llvm::Function::Create(llvmType, linkage, identifier, module);
    }

    Address Function::call(const Vector<Address>& args) const {
        if (parameters.size() < args.size()) {
            throw CompileError(
                "Too many arguments to call of {0}: expected: {1}, got: {2}", name(), parameters.size(), args.size());
        }
        // fill in supplied params
        Vector<llvm::Value*> coercedArgs;
        int idx = 0;
        for (const auto& arg : args) {
            auto expectedType = parameters[idx++].type->ops();
            coercedArgs.push_back(expectedType->coerce(arg));
        }

        // fill in default params
        for (auto argIdx = coercedArgs.size(); argIdx < parameters.size(); ++argIdx) {
            const auto& param = parameters[argIdx];
            if (!param.initializer) {
                throw CompileError("Missing argument {0}({1}) of type {2} to {3}",
                                   argIdx,
                                   param.name,
                                   Types::to_string(param.type),
                                   identifier);
            }
            coercedArgs.push_back(param.type->ops()->coerce(param.initializer));
        }
        auto functionType = llvm::cast<llvm::FunctionType>(Types::get(func_type.get()));
        return Address{ret_type, SemaContext::get().ir()->CreateCall(functionType, llvm_function, coercedArgs)};
    }

    UserFunction::UserFunction(llvm::Module& module, const Ident& name, Ref<Type> return_type, const Params& params)
        : Function(module, name, return_type, params) {
        body = llvm::BasicBlock::Create(module.getContext(), "entry", llvm_function);
        ir_builder = Ref<llvm::IRBuilder<>>::create(body);

        // Set up return block and return instruction
        return_expr = llvm::BasicBlock::Create(module.getContext(), "return", llvm_function);
        auto builder = Ref<llvm::IRBuilder<>>::create(return_expr);
        builder->SetInsertPoint(return_expr);
        if (return_type != Types::Void) {
            return_value = Address{return_type, ir_builder->CreateAlloca(*return_type, nullptr, "retval")};
            builder->CreateRet(builder->CreateLoad(*ret_type, return_value));
        } else {
            builder->CreateRetVoid();
        }
    }

    llvm::BasicBlock* UserFunction::append_block(const Ident& name) {
        auto block = llvm::BasicBlock::Create(llvm_function->getContext(), name, llvm_function, return_expr);
        return block;
    }

    bool UserFunction::count_arg_refs() const {
        return true;
    }

    bool Method::count_arg_refs() const {
        if (!UserFunction::count_arg_refs())
            return false;

        if (identifier.find(".__") != std::string::npos)
            return false;

        return true;
    }
} // namespace pepper
