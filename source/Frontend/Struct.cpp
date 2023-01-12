
#include "Frontend/Struct.h"

#include "CodeGen/Value.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Frontend/Context.h"
#include "Frontend/TypeOps.h"
#include "LLVMUtils.h"
#include "llvm/IR/DataLayout.h"

namespace pepper {

    Struct::Struct(const Ident& name, const Params& fields, const Params& newParams)
        : Identifier(name) {
        // Create the LLVM struct type out of the field types
        Vector<llvm::Type*> fieldTypes = Query(fields).select<llvm::Type*>([](auto& f) { return *f.ParamType; });
        auto llvmType = llvm::StructType::create(fieldTypes, Identifier);

        // Add underlying struct as struct.<struct>
        StructTy = Ref<StructType>::New(this, "struct." + name, llvmType);
        Types::add(StructTy);
        // Add ref type as <struct>
        RefTy = Ref<RefType>::New(StructTy);
        Types::add(RefTy);
        NewInstance = Ref<UserFunction>::New(name, RefTy, newParams);

        setFields(fields);

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(llvmType));
        Size = structLayout->getSizeInBytes();
        Align = structLayout->getAlignment().value();
    }

    Ref<Struct> Struct::New(const Ident& name, const Params& fields, const Params& newParams) {
        Ref<Struct> newStruct = Ref<Struct>::New(name, fields, newParams);
        Context::get().globals()->Structs[name] = newStruct;
        return newStruct;
    }

    Ref<Struct> Struct::get(const Ident& name) {
        return Context::get().globals()->Structs.lookup(name);
    }

    Value Struct::getMember(llvm::Value* instance, const Ident& name) const {
        if (auto field = getField(instance, name))
            return field;
        return getMethod(name);
    }

    Value Struct::getField(llvm::Value* instance, const Ident& name) const {
        auto fieldIt = Fields.find(name);
        if (fieldIt != Fields.end()) {
            int idx = (int)std::distance(Fields.begin(), fieldIt);
            return getField(instance, idx, fieldIt->second);
        }
        return Value{};
    }

    Value Struct::getField(llvm::Value* instance, int idx, const Param& field) const {
        return Value(field.ParamType, ir()->CreateStructGEP(*StructTy, instance, idx, field.ParamName));
    }

    Value Struct::getMethod(const Ident& name) const {
        auto it = Methods.find(name);
        if (it != Methods.end()) {
            auto method = it->second;
            return Value{method->type(), method->function(), method->name()};
        }
        return Value{};
    }

    class StructTypeOps : public TypeOps {
        DECLARE_RTTI(StructTypeOps, TypeOps);

        const Struct* Struct;

      public:
        StructTypeOps(Ref<Type> type)
            : TypeOps(type) {
            Struct = Ty.as<StructType>()->StructDesc;
        }

        Value coerce(Value) const override {
            throw CompileError("Coercion between structs is not supported");
        }
    };

    StructType::StructType(const Struct* st, const Ident& name, llvm::Type* type)
        : Type(name, type)
        , StructDesc(st) {
    }

    Ref<RefType> StructType::refType() const {
        return StructDesc->refType();
    }

    TypeOps* StructType::ops() {
        if (!Ops)
            Ops = Ref<StructTypeOps>::New(shared_from_this());
        return Ops.get();
    }

    class RefTypeOps : public PointerTypeOps {
        DECLARE_RTTI(RefTypeOps, PointerTypeOps);

      public:
        using PointerTypeOps::PointerTypeOps;

        void init(Value lhs, Value rhs) const override {
            rhs = coerce(rhs);
            ir()->CreateStore(rhs, lhs);
            auto st = Ty.as<RefType>()->structType()->StructDesc;
            auto acquire = st->method("__acquire");
            acquire->call({rhs});
        }

        Value assign(Value lhs, Value rhs) const override {
            rhs = coerce(rhs);
            auto st = Ty.as<RefType>()->structType()->StructDesc;
            auto acquire = st->method("__acquire");
            auto release = st->method("__release");
            acquire->call({rhs});
            release->call({lhs});
            ir()->CreateStore(rhs, lhs);
            return lhs;
        }
    };

    RefType::RefType(Ref<StructType> structType)
        : PointerType(structType->StructDesc->name(), structType)
        , StructTy(structType) {
    }

    Ref<StructType> RefType::structType() const {
        return pointeeType().as<StructType>();
    }

    TypeOps* RefType::ops() {
        if (!Ops)
            Ops = Ref<RefTypeOps>::New(shared_from_this());
        return Ops.get();
    }

} // namespace pepper
