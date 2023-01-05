
#pragma once

#include <map>
#include <memory>

#include "Codegen/Function.h"
#include "Codegen/Param.h"
#include "Codegen/Types.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {
    class StructTypeInfo;

    class Struct : public std::enable_shared_from_this<Struct> {
        Ident Identifier;
        Ref<StructTypeInfo> StructType;
        Ref<StructTypeInfo> RefType;
        Ref<Function> NewInstance;
        std::map<Ident, Param> Fields;
        llvm::StringMap<Ref<Method>> Methods;
        size_t Size;
        size_t Align;

      public:
        Struct(const Ident& name, const Params& fields = {}, const Params& newParams = {});
        static Ref<Struct> New(const Ident& name, const Params& fields = {}, const Params& newParams = {});

        Ref<StructTypeInfo> type() const {
            return RefType;
        }

        Ref<StructTypeInfo> structType() const {
            return StructType;
        }

        const Ident& name() const {
            return Identifier;
        }

        void setFields(const Params& fields) {
            for (auto& field : fields) {
                Fields.insert_or_assign(field.ParamName, field);
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

        llvm::Value* getMember(llvm::Value* instance, const Ident& name) const;
        llvm::Value* getField(llvm::Value* instance, const Ident& name) const;
        llvm::Value* getField(llvm::Value* instance, int idx, const Param& field) const;
        llvm::Function* getMethod(const Ident& name) const;

        Ref<Function> instanceNew() const {
            return NewInstance;
        }

        Ref<Function> initializer() const {
            return method("__init");
        }

        Ref<Function> constructor() const {
            return method("__ctor");
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

    class StructTypeInfo : public TypeInfo {
        DECLARE_RTTI(StructTypeInfo, TypeInfo);

        const Struct* StructDesc;
        Ref<TypeOps> Ops;

      public:
        StructTypeInfo(const Struct* st, const Ident& name, llvm::Type* type);

        bool isStruct() const override {
            return true;
        }

        TypeOps* ops() override;
    };
} // namespace pepper
