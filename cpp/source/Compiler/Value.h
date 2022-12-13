
#pragma once

#include "Core/Common.h"
#include <string>

class Type;

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
} // namespace llvm

class Value {
    Ref<Type> ValueType;
    llvm::Value* ValueRef;
    const std::string Name;

    Value(Ref<Type> type, llvm::Value* value, const std::string& name = "");
    Value(Ref<Type> type, Ref<Value> value, const std::string& name = "");

  public:
    operator llvm::Value*() const {
        return ValueRef;
    }

    static Ref<Value> New(Ref<Type>, llvm::Value* value, const std::string& name = "");
    static Ref<Value> New(Ref<Type>, Ref<Value> value, const std::string& name = "");

    Ref<Type> type() const {
        return ValueType;
    }

    const std::string& name() const {
        return Name;
    }

    llvm::Value* store(Ref<Value> value, llvm::IRBuilderBase* builder = nullptr);
    llvm::Value* load(llvm::IRBuilderBase* builder = nullptr);
};
