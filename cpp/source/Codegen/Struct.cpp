
#include "Codegen/Struct.h"

#include "Codegen/Context.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Module.h"

namespace pepper {
    llvm::StringMap<Ref<Struct>> Struct::Structs;

    Struct::Struct(Ref<Type> type, const Name& name)
        : StructType(type)
        , Identifier(name) {
        Structs[name] = shared_from_this();

        // deal with params at some point
        New = Ref<UserFunction>::New(name, StructType);

        // compute size from data layout
        auto module = Context::get().module();
        auto dataLayout = module->getDataLayout();
        Size = dataLayout.getStructLayout(static_cast<llvm::StructType*>(type->llvmType()))->getSizeInBytes();
    }
} // namespace pepper
