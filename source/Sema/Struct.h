
#pragma once

#include <map>
#include <memory>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Function.h"
#include "Param.h"
#include "Types.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {

    class Struct;

    class StructType : public Type {
        DECLARE_RTTI(StructType, Type);

        const Struct* struct_desc;
        Ref<Operations> struct_ops;

      public:
        StructType(const Struct* st, const Ident& name, llvm::Type* type);

        bool is_struct() const override {
            return true;
        }

        Ref<class RefType> ref_type() const;

        Type::Size size_in_bits() const override;

        Operations* ops() override;
    };

    class RefType : public PointerType {
        DECLARE_RTTI(RefType, PointerType);

        Ref<StructType> struct_type;
        Ref<Operations> struct_ops;

      public:
        RefType(Ref<StructType> struct_type);

        bool is_struct() const override {
            return true;
        }

        Ref<StructType> type() const;

        Operations* ops() override;
    };

    class Struct : public std::enable_shared_from_this<Struct> {
        Ident struct_name;
        Ref<StructType> struct_type;
        Ref<RefType> ref;
        Ref<Function> construct;
        Vector<Param> field_members;
        llvm::StringMap<Ref<Method>> method_members;
        Type::Size type_size;
        Type::Size type_align;

      public:
        Struct(llvm::Module& module, const Ident& name, const Params& fields = {}, const Params& ctorParams = {});
        static Ref<Struct> create(
            llvm::Module& module, const Ident& name, const Params& fields = {}, const Params& ctorParams = {});

        Ref<RefType> ref_type() const {
            return ref;
        }

        Ref<StructType> type() const {
            return struct_type;
        }

        const Ident& name() const {
            return struct_name;
        }

        void set_fields(const Params& fields) {
            field_members = fields;
        }

        Params fields() const {
            return field_members;
        }

        void set_methods(const Vector<Ref<Method>>& methods) {
            for (auto& method : methods) {
                add_method(method);
            }
        }

        void add_method(Ref<Method> method, const Ident& realName = "") {
            method_members[method->name()] = method;
            if (realName.size())
                method_members[realName] = method;
        }

        Ref<Function> method(const Ident& name) const {
            return method_members.lookup(name);
        }

        Vector<Ref<Method>> methods() const {
            Vector<Ref<Method>> ms;
            for (auto& m : method_members) {
                ms.push_back(m.getValue());
            }
            return ms;
        }

        Address get_member(llvm::Value* instance, const Ident& name) const;
        Address get_field(llvm::Value* instance, const Ident& name) const;
        Address get_field(llvm::Value* instance, int idx, const Param& field) const;
        Address get_method(const Ident& name) const;

        Ref<Function> constructor() const {
            return construct;
        }

        Ref<Function> destructor() const {
            return method("__dtor");
        }

        Type::Size size() const {
            return type_size;
        }

        Type::Size size_in_bits() const {
            return type_size * 8;
        }

        Type::Size align() const {
            return type_align;
        }

        Type::Size align_in_bits() const {
            return type_align * 8;
        }

        static Ref<Struct> get(const Ident& name);
    };
} // namespace pepper
