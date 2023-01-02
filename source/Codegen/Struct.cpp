
#include "Codegen/Struct.h"

#include "Codegen/Context.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"

namespace pepper {

    Struct::Struct(Ref<TypeInfo> type, const Ident& name, const Params& newParams)
        : StructType(type)
        , Identifier(name) {
        // deal with params at some point
        NewInstance = Ref<UserFunction>::New(name, Types::get(StructType->name()), newParams);

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        auto structLayout = dataLayout.getStructLayout(cast<llvm::StructType>(type->llvmType()));
        Size = structLayout->getSizeInBytes();
        Align = structLayout->getAlignment().value();
    }

    Ref<Struct> Struct::New(Ref<TypeInfo> type, const Ident& name, const Params& newParams) {
        Ref<Struct> newStruct = Ref<Struct>::New(type, name, newParams);
        Context::get().globals()->Structs[name] = newStruct;
        return newStruct;
    }

    Ref<Struct> Struct::get(const Ident& name) {
        return Context::get().globals()->Structs.lookup(name);
    }

    llvm::Value* Struct::getMember(llvm::Value* instance, const Ident& name) const {
        if (auto field = getField(instance, name))
            return field;
        return getMethod(instance, name);
    }

    llvm::Value* Struct::getField(llvm::Value* instance, const Ident& name) const {
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

    llvm::Function* Struct::getMethod(llvm::Value* instance, const Ident& name) const {
        auto it = Methods.find(name);
        if (it != Methods.end()) {
            auto method = it->second;
            return method->function();
        }
        return nullptr;
    }
} // namespace pepper
