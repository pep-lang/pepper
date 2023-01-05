
#include "Codegen/Struct.h"

#include "Codegen/Context.h"
#include "Codegen/IR/Value.h"
#include "Codegen/TypeOps.h"
#include "Core/Exceptions.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"

namespace pepper {

    Struct::Struct(Ref<TypeInfo> type, const Ident& name, const Params& newParams)
        : StructType(type)
        , Identifier(name) {
        // deal with params at some point
        NewInstance = Ref<UserFunction>::New(name, Types::get(StructType->name()), newParams);

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(type->llvmType()));
        Size = structLayout->getSizeInBytes();
        Align = structLayout->getAlignment().value();
    }

    Ref<Struct> Struct::New(Ref<TypeInfo> type, const Ident& name, const Params& newParams) {
        Ref<Struct> newStruct = Ref<Struct>::New(type, name, newParams);
        Context::get().globals()->Structs[name] = newStruct;
        return newStruct;
    }

    Ref<Struct> Struct::get(const Ident& name) {
        return Context::get().globals()->Structs.lookup(name);
    }

    llvm::Value* Struct::getMember(llvm::Value* instance, const Ident& name) const {
        if (auto field = getField(instance, name))
            return field;
        return getMethod(name);
    }

    llvm::Value* Struct::getField(llvm::Value* instance, const Ident& name) const {
        auto fieldIt = Fields.find(name);
        if (fieldIt != Fields.end()) {
            int idx = (int)std::distance(Fields.begin(), fieldIt);
            return getField(instance, idx, fieldIt->second);
        }
        return nullptr;
    }

    llvm::Value* Struct::getField(llvm::Value* instance, int idx, const Param& field) const {
        return Context::ir()->CreateStructGEP(*StructType, instance, idx, field.ParamName);
    }

    llvm::Function* Struct::getMethod(const Ident& name) const {
        auto it = Methods.find(name);
        if (it != Methods.end()) {
            auto method = it->second;
            return method->function();
        }
        return nullptr;
    }

    class StructTypeOps : public TypeOps {
        DECLARE_RTTI(StructTypeOps, TypeOps);

        static Ref<llvm::IRBuilderBase> ir() {
            return Context::get().locals()->builder();
        }

        Ref<Struct> Struct;

      public:
        StructTypeOps(Ref<TypeInfo> type)
            : TypeOps(type) {
            Struct = Type.as<StructTypeInfo>()->Struct;
        }

        Value coerce(Value value) const override {
            if (value.Ty == Type) {
                return value;
            }
            throw CompileError("Coercion between structs is not supported");
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateICmpEQ(coerce(lhs), coerce(rhs))};
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateICmpNE(coerce(lhs), coerce(rhs))};
        }

        Value assign(Value lhs, Value rhs) const override {
            auto acquire = Struct->getMethod("__acquire");
            // rhs.__acquire(lhs), i.e. rhs is being acquired by lhs, lhs may have to release its prior value
            ir()->CreateCall(acquire->getFunctionType(), acquire, {rhs, lhs});
            ir()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value asBool(Value value) const override {
            auto zero = llvm::ConstantInt::getFalse(*Type);
            auto valAsInt = ir()->CreatePtrToInt(value, *Types::Int64);
            return Value{Types::Bool, ir()->CreateICmpNE(zero, valAsInt, "bool")};
        }
    };

    TypeOps* StructTypeInfo::ops() {
        if (!Ops)
            Ops = Ref<StructTypeOps>::New(shared_from_this());
        return Ops.get();
    }
} // namespace pepper
