
#include "Type.h"

#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

Type::alloc(llvm::IRBuilderBase* builder) const {
    builder = builder ? builder : Context::get().Locals.LocalRegisters();
}
