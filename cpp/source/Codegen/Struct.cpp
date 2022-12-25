
#include "Codegen/Struct.h"

#include "Codegen/Context.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Module.h"

namespace pepper {
    llvm::StringMap<Ref<Struct>> Struct::Structs;

    Struct::Struct(Ref<Type> type, const Name& name)
        : StructType(type)
        , Identifier(name) {
        // deal with params at some point
        NewInstance = Ref<UserFunction>::New(name, StructType);

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        Size = dataLayout.getStructLayout(static_cast<llvm::StructType*>(type->llvmType()))->getSizeInBytes();
    }

    Ref<Struct> Struct::New(Ref<Type> type, const Name& name) {
        Ref<Struct> newStruct = Ref<Struct>::New(type, name);
        Structs[name] = newStruct;
        return newStruct;
    }
} // namespace pepper
