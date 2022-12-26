
#include "Codegen/Struct.h"

#include "Codegen/Context.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"

namespace pepper {
    llvm::StringMap<Ref<Struct>> Struct::Structs;

    Struct::Struct(Ref<Type> type, const Name& name)
        : StructType(type)
        , Identifier(name) {
        // deal with params at some point
        NewInstance = Ref<UserFunction>::New(name, Types::get(StructType->name()));

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(type->llvmType()));
        Size = structLayout->getSizeInBytes();
        Align = structLayout->getAlignment().value();
    }

    Ref<Struct> Struct::New(Ref<Type> type, const Name& name) {
        Ref<Struct> newStruct = Ref<Struct>::New(type, name);
        Structs[name] = newStruct;
        return newStruct;
    }

    llvm::Value* Struct::getMember(llvm::Value* instance, const Name& name) const {
        if (auto field = getField(instance, name))
            return field;
        return getMethod(instance, name);
    }

    llvm::Value* Struct::getField(llvm::Value* instance, const Name& name) const {
        auto fieldIt = Fields.find(name);
        if (fieldIt != Fields.end()) {
            int idx = std::distance(Fields.begin(), fieldIt);
            return getField(instance, idx, fieldIt->second);
        }
        return nullptr;
    }

    llvm::Value* Struct::getField(llvm::Value* instance, int idx, const Param& field) const {
        return Context::ir()->CreateStructGEP(*StructType, instance, idx, field.ParamName);
    }

    llvm::Function* Struct::getMethod(llvm::Value* instance, const Name& name) const {
        auto it = Methods.find(name);
        if (it != Methods.end()) {
            auto method = it->second;
            return method->function();
        }
        return nullptr;
    }
} // namespace pepper
