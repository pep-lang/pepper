
#pragma once

#include <map>
#include <memory>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Frontend/Function.h"
#include "Frontend/Param.h"
#include "Frontend/Types.h"
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

        unsigned size() const override;

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
        std::map<Ident, Param> Fields;
        llvm::StringMap<Ref<Method>> Methods;
        size_t Size;
        size_t Align;

      public:
        Struct(const Ident& name, const Params& fields = {}, const Params& ctorParams = {});
        static Ref<Struct> New(const Ident& name, const Params& fields = {}, const Params& ctorParams = {});

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
            for (auto& field : fields) {
                Fields.insert_or_assign(field.Name, field);
            }
        }

        Params fields() const {
            Params fs;
            for (auto& field : Fields) {
                fs.push_back(field.second);
            }
            return fs;
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

        size_t size() const {
            return Size;
        }

        size_t align() const {
            return Align;
        }

        static Ref<Struct> get(const Ident& name);
    };
} // namespace pepper
