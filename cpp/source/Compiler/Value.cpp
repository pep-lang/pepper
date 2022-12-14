
#include "Compiler/Value.h"

#include "Compiler/Context.h"
#include "Compiler/Scope.h"
#include "Compiler/Type.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

Ref<Value> Value::New(Ref<Type> type, llvm::Value* value, const std::string& name) {
    struct RValue : public Value {
        RValue(Ref<Type> type, llvm::Value* value, const std::string& name)
            : Value(type, value, name) {
        }
    };

    return std::make_shared<RValue>(type, value, name);
}

Ref<Value> Value::New(Ref<Type> type, Ref<Value> value, const std::string& name) {
    struct LValue : public Value {
        LValue(Ref<Type> type, Ref<Value> value, const std::string& name)
            : Value(type, value, name) {
        }
    };

    return std::make_shared<LValue>(type, value, name);
}

Value::Value(Ref<Type> type, llvm::Value* value, const std::string& name)
    : ValueType(type)
    , ValueRef(value)
    , Name(name) {
}

Value::Value(Ref<Type> type, Ref<Value> value, const std::string& name)
    : ValueType(type)
    , Name(name) {
    store(value);
}

llvm::Value* Value::store(Ref<Value> value, llvm::IRBuilderBase* builder) {
    builder = builder ? builder : Context::get().locals()->localRegisters().get();
    return builder->CreateAlloca(*this->type(), nullptr, Name.c_str());
}

llvm::Value* Value::load(llvm::IRBuilderBase* builder) {
    builder = builder ? builder : Context::get().locals()->localRegisters().get();
    return builder->CreateAlloca(*this->type(), nullptr, Name.c_str());
}
