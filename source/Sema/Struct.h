
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

        const Struct* StructDesc;
        Ref<Operations> Ops;

      public:
        StructType(const Struct* st, const Ident& name, llvm::Type* type);

        bool isStruct() const override {
            return true;
        }

        Ref<class RefType> refType() const;

        Type::Size sizeInBits() const override;

        Operations* ops() override;
    };

    class RefType : public PointerType {
        DECLARE_RTTI(RefType, PointerType);

        Ref<StructType> StructTy;
        Ref<Operations> Ops;

      public:
        RefType(Ref<StructType> structType);

        bool isStruct() const override {
            return true;
        }

        Ref<StructType> structType() const;

        Operations* ops() override;
    };

    class Struct : public std::enable_shared_from_this<Struct> {
        Ident Name;
        Ref<StructType> StructTy;
        Ref<RefType> RefTy;
        Ref<Function> Constructor;
        Vector<Param> Fields;
        llvm::StringMap<Ref<Method>> Methods;
        Type::Size Size;
        Type::Size Align;

      public:
        Struct(llvm::Module& module, const Ident& name, const Params& fields = {}, const Params& ctorParams = {});
        static Ref<Struct> New(
            llvm::Module& module, const Ident& name, const Params& fields = {}, const Params& ctorParams = {});

        Ref<RefType> refType() const {
            return RefTy;
        }

        Ref<StructType> structType() const {
            return StructTy;
        }

        const Ident& name() const {
            return Name;
        }

        void setFields(const Params& fields) {
            Fields = fields;
        }

        Params fields() const {
            return Fields;
        }

        void setMethods(const Vector<Ref<Method>>& methods) {
            for (auto& method : methods) {
                addMethod(method);
            }
        }

        void addMethod(Ref<Method> method, const Ident& realName = "") {
            Methods[method->name()] = method;
            if (realName.size())
                Methods[realName] = method;
        }

        Ref<Function> method(const Ident& name) const {
            return Methods.lookup(name);
        }

        Vector<Ref<Method>> methods() const {
            Vector<Ref<Method>> ms;
            for (auto& m : Methods) {
                ms.push_back(m.getValue());
            }
            return ms;
        }

        Address getMember(llvm::Value* instance, const Ident& name) const;
        Address getField(llvm::Value* instance, const Ident& name) const;
        Address getField(llvm::Value* instance, int idx, const Param& field) const;
        Address getMethod(const Ident& name) const;

        Ref<Function> constructor() const {
            return Constructor;
        }

        Ref<Function> destructor() const {
            return method("__dtor");
        }

        Type::Size size() const {
            return Size;
        }

        Type::Size sizeInBits() const {
            return Size * 8;
        }

        Type::Size align() const {
            return Align;
        }

        Type::Size alignInBits() const {
            return Align * 8;
        }

        static Ref<Struct> get(const Ident& name);
    };
} // namespace pepper
