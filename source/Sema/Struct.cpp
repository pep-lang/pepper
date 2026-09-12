
#include "Struct.h"

#include "CodeGen/LLVM/Address.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/Query.h"
#include "Operations.h"
#include "SemaContext.h"
#include "llvm/IR/DataLayout.h"

namespace pepper {

    Struct::Struct(llvm::Module& module, const Ident& name, const Params& fields, const Params& ctorParams)
        : struct_name(name)
        , type_size(Type::Size::Fixed(0))
        , type_align(Type::Size::Fixed(0)) {
        // Create the LLVM struct type out of the field types
        Vector<llvm::Type*> fieldTypes =
            Query(fields).select<llvm::Type*>([](auto& f) { return Types::get(f.type.get()); });
        auto llvmType = llvm::StructType::create(fieldTypes, struct_name);

        // Add underlying struct as struct.<struct>
        struct_type = Ref<StructType>::create(this, "struct." + name, llvmType);
        Types::add(struct_type);
        // Add ref type as <struct>
        ref = Ref<RefType>::create(struct_type);
        Types::add(ref);
        auto pointerTy = Ref<PointerType>::create(ref);
        Types::add(pointerTy);
        construct = Ref<UserFunction>::create(module, name, ref, ctorParams);

        set_fields(fields);

        // compute size from data layout
        auto dataLayout = module.getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(llvmType));
        type_size = Type::Size::Fixed(structLayout->getSizeInBits() / 8);
        type_align = Type::Size::Fixed(structLayout->getAlignment().value());
    }

    Ref<Struct> Struct::create(llvm::Module& module, const Ident& name, const Params& fields, const Params& newParams) {
        Ref<Struct> newStruct = Ref<Struct>::create(module, name, fields, newParams);
        auto globals = SemaContext::get().globals();
        globals->structs[name] = newStruct;
        globals->functions[newStruct->construct->name()] = newStruct->construct;
        return newStruct;
    }

    Ref<Struct> Struct::get(const Ident& name) {
        return SemaContext::get().globals()->structs.lookup(name);
    }

    Address Struct::get_member(llvm::Value* instance, const Ident& name) const {
        if (auto field = get_field(instance, name))
            return field;
        return get_method(name);
    }

    Address Struct::get_field(llvm::Value* instance, const Ident& name) const {
        auto idx = Query(field_members).index_of([&](auto& f) { return f.name == name; });
        if (idx != -1) {
            return get_field(instance, (int)idx, field_members[idx]);
        }
        return Address{};
    }

    Address Struct::get_field(llvm::Value* instance, int idx, const Param& field) const {
        return Address(field.type, ir()->CreateStructGEP(*struct_type, instance, idx, field.name));
    }

    Address Struct::get_method(const Ident& name) const {
        auto it = method_members.find(name);
        if (it != method_members.end()) {
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
            Struct = operand_type.as<StructType>()->struct_desc;
        }

        Address coerce(Address) const override {
            throw CompileError("Coercion between structs is not supported");
        }
    };

    StructType::StructType(const Struct* st, const Ident& name, llvm::Type* type)
        : Type(name, type)
        , struct_desc(st) {}

    Ref<RefType> StructType::ref_type() const {
        return struct_desc->ref_type();
    }

    Type::Size StructType::size_in_bits() const {
        return struct_desc->size_in_bits();
    }

    Operations* StructType::ops() {
        if (!struct_ops)
            struct_ops = Ref<StructTypeOps>::create(shared_from_this());
        return struct_ops.get();
    }

    class RefTypeOps : public PointerOperations {
        DECLARE_RTTI(RefTypeOps, PointerOperations);

      public:
        using PointerOperations::PointerOperations;

        void init(Address lhs, Address rhs) const override {
            rhs = coerce(rhs);
            ir()->CreateStore(rhs, lhs);
            auto st = operand_type.as<RefType>()->type()->struct_desc;
            auto acquire = st->method("__acquire");
            acquire->call({rhs});
        }

        Address assign(Address lhs, Address rhs) const override {
            rhs = coerce(rhs);
            auto st = operand_type.as<RefType>()->type()->struct_desc;
            auto acquire = st->method("__acquire");
            auto release = st->method("__release");
            acquire->call({rhs});
            release->call({lhs});
            ir()->CreateStore(rhs, lhs);
            return lhs;
        }
    };

    RefType::RefType(Ref<StructType> struct_type)
        : PointerType(struct_type->struct_desc->name(), struct_type)
        , struct_type(struct_type) {}

    Ref<StructType> RefType::type() const {
        return pointee_type().as<StructType>();
    }

    Operations* RefType::ops() {
        if (!struct_ops)
            struct_ops = Ref<RefTypeOps>::create(shared_from_this());
        return struct_ops.get();
    }

} // namespace pepper
