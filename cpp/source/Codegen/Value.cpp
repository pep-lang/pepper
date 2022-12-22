
#include "Codegen/Value.h"

#include "Codegen/Scope.h"
#include "Compiler/Context.h"
#include "Compiler/Type.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    //    Ref<Value> Value::New(Ref<Type> type, llvm::Value* value, const std::string& name) {
    //        struct RValue : public Value {
    //            RValue(Ref<Type> type, llvm::Value* value, const std::string& name)
    //                : Value(type, value, name) {
    //            }
    //        };
    //
    //        return Ref<RValue>::create(type, value, name);
    //    }
    //
    //    Ref<Value> Value::New(Ref<Type> type, Ref<Value> value, const std::string& name) {
    //        struct LValue : public Value {
    //            LValue(Ref<Type> type, Ref<Value> value, const std::string& name)
    //                : Value(type, value, name) {
    //            }
    //        };
    //
    //        return Ref<LValue>::create(type, value, name);
    //    }
    //
    //    Value::Value(Ref<Type> type, llvm::Value* value, const std::string& name)
    //        : Symbol(type, name)
    //        , ValueRef(value) {
    //    }
    //
    //    Value::Value(Ref<Type> type, Ref<Value> value, const std::string& name)
    //        : Symbol(type, name) {
    //        store(value);
    //    }
    //
    //    llvm::Value* Value::store(Ref<Value> value, llvm::IRBuilderBase* builder) {
    //        builder = builder ? builder : Context::get().locals()->registers().get();
    //        return builder->CreateAlloca(*this->type(), nullptr, Name.c_str());
    //    }
    //
    //    llvm::Value* Value::load(llvm::IRBuilderBase* builder) {
    //        builder = builder ? builder : Context::get().locals()->registers().get();
    //        return builder->CreateAlloca(*this->type(), nullptr, Name.c_str());
    //    }

} // namespace pepper
