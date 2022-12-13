
#include "Compiler/Type.h"

#include "Compiler/Context.h"
#include "Compiler/Scope.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

llvm::Value* Type::alloc(llvm::IRBuilderBase* builder) const {
    builder = builder ? builder : Context::get().locals()->localRegisters().get();
    return nullptr;
}
