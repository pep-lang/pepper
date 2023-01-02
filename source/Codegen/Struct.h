
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
    class Struct : public std::enable_shared_from_this<Struct> {
        Ident Identifier;
        Ref<TypeInfo> StructType;
        Ref<Function> NewInstance;
        std::map<Ident, Param> Fields;
        llvm::StringMap<Ref<Method>> Methods;
        size_t Size;
        size_t Align;

        static llvm::StringMap<Ref<Struct>> Structs;

      public:
        Struct(Ref<TypeInfo> type, const Ident& name, const Params& newParams = {});
        static Ref<Struct> New(Ref<TypeInfo> type, const Ident& name, const Params& newParams = {});

        Ref<TypeInfo> type() const {
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
        llvm::Function* getMethod(llvm::Value* instance, const Ident& name) const;

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

        static Ref<Struct> get(const Ident& name) {
            return Structs.lookup(name);
        }
    };
} // namespace pepper
