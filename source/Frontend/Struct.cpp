
#include "Frontend/Struct.h"

#include "CodeGen/Address.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Frontend/Context.h"
#include "Frontend/Operations.h"
#include "LLVMUtils.h"
#include "llvm/IR/DataLayout.h"

namespace pepper {

    Struct::Struct(llvm::Module& module, const Ident& name, const Params& fields, const Params& ctorParams)
        : Name(name) {
        // Create the LLVM struct type out of the field types
        Vector<llvm::Type*> fieldTypes = Query(fields).select<llvm::Type*>([](auto& f) { return *f.Type; });
        auto llvmType = llvm::StructType::create(fieldTypes, Name);

        // Add underlying struct as struct.<struct>
        StructTy = Ref<StructType>::New(this, "struct." + name, llvmType);
        Types::add(StructTy);
        // Add ref type as <struct>
        RefTy = Ref<RefType>::New(StructTy);
        Types::add(RefTy);
        Constructor = Ref<UserFunction>::New(module, name, RefTy, ctorParams);

        setFields(fields);

        // compute size from data layout
        auto dataLayout = module.getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(llvmType));
        Size = structLayout->getSizeInBytes();
        Align = structLayout->getAlignment().value();
    }

    Ref<Struct> Struct::New(llvm::Module& module, const Ident& name, const Params& fields, const Params& newParams) {
        Ref<Struct> newStruct = Ref<Struct>::New(module, name, fields, newParams);
        Context::get().globals()->Structs[name] = newStruct;
        return newStruct;
    }

    Ref<Struct> Struct::get(const Ident& name) {
        return Context::get().globals()->Structs.lookup(name);
    }

    Address Struct::getMember(llvm::Value* instance, const Ident& name) const {
        if (auto field = getField(instance, name))
            return field;
        return getMethod(name);
    }

    Address Struct::getField(llvm::Value* instance, const Ident& name) const {
        auto fieldIt = Fields.find(name);
        if (fieldIt != Fields.end()) {
            int idx = (int)std::distance(Fields.begin(), fieldIt);
            return getField(instance, idx, fieldIt->second);
        }
        return Address{};
    }

    Address Struct::getField(llvm::Value* instance, int idx, const Param& field) const {
        return Address(field.Type, ir()->CreateStructGEP(*StructTy, instance, idx, field.Name));
    }

    Address Struct::getMethod(const Ident& name) const {
        auto it = Methods.find(name);
        if (it != Methods.end()) {
            auto method = it->second;
            return Address{method->type(), method->function(), method->name()};
        }
        return Address{};
    }

    class StructTypeOps : public Operations {
        DECLARE_RTTI(StructTypeOps, Operations);

        const Struct* Struct;

      public:
        StructTypeOps(Ref<Type> type)
            : Operations(type) {
            Struct = Ty.as<StructType>()->StructDesc;
        }

        Address coerce(Address) const override {
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

    unsigned StructType::size() const {
        return StructDesc->size();
    }

    Operations* StructType::ops() {
        if (!Ops)
            Ops = Ref<StructTypeOps>::New(shared_from_this());
        return Ops.get();
    }

    class RefTypeOps : public PointerOperations {
        DECLARE_RTTI(RefTypeOps, PointerOperations);

      public:
        using PointerOperations::PointerOperations;

        void init(Address lhs, Address rhs) const override {
            rhs = coerce(rhs);
            ir()->CreateStore(rhs, lhs);
            auto st = Ty.as<RefType>()->structType()->StructDesc;
            auto acquire = st->method("__acquire");
            acquire->call({rhs});
        }

        Address assign(Address lhs, Address rhs) const override {
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

    Operations* RefType::ops() {
        if (!Ops)
            Ops = Ref<RefTypeOps>::New(shared_from_this());
        return Ops.get();
    }

} // namespace pepper
