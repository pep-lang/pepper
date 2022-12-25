
#pragma once

#include <map>
#include <memory>

#include "Codegen/Function.h"
#include "Codegen/Param.h"
#include "Codegen/Types.h"
#include "Core/Common.h"
#include "Core/Name.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {
    class Struct : public std::enable_shared_from_this<Struct> {
        Name Identifier;
        Ref<Type> StructType;
        Ref<Function> NewInstance;
        std::map<Name, Param> Fields;
        llvm::StringMap<Ref<Method>> Methods;
        size_t Size;

        static llvm::StringMap<Ref<Struct>> Structs;

      public:
        Struct(Ref<Type> type, const Name& name);
        static Ref<Struct> New(Ref<Type> type, const Name& name);

        Ref<Type> type() const {
            return StructType;
        }

        const Name& name() const {
            return Identifier;
        }

        void setFields(const Params& fields) {
            for (auto& field : fields) {
                Fields.insert_or_assign(field.ParamName, field);
            }
        }

        //        const Param& field(const Name& name) const {
        //            auto it = Fields.find(name);
        //            if (it != Fields.end()) {
        //                return it->second;
        //            }
        //            return nullptr;
        //        }

        Params fields() const {
            Params fs;
            for (auto& field : Fields) {
                fs.push_back(field.second);
            }
            return fs;
        }

        void setMethods(const llvm::SmallVector<Ref<Method>>& methods) {
            for (auto& method : methods) {
                addMethod(method);
            }
        }

        void addMethod(Ref<Method> method) {
            Methods[method->name()] = method;
        }

        Ref<Function> method(const Name& name) const {
            return Methods.lookup(name);
        }

        llvm::SmallVector<Ref<Method>> methods() const {
            llvm::SmallVector<Ref<Method>> ms;
            for (auto& m : Methods) {
                ms.push_back(m.getValue());
            }
            return ms;
        }

        llvm::Value* getMember(llvm::Value* instance, const Name& name) const;
        llvm::Value* getField(llvm::Value* instance, const Name& name) const;
        llvm::Value* getField(llvm::Value* instance, int idx, const Param& field) const;
        llvm::Function* getMethod(llvm::Value* instance, const Name& name) const;

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

        static Ref<Struct> get(const Name& name) {
            return Structs.lookup(name);
        }
    };
} // namespace pepper
