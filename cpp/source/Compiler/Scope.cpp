
#include "Scope.h"

#include "llvm/IR/IRBuilder.h"

namespace pepper {

    std::shared_ptr<llvm::IRBuilderBase> Scope::localRegisters() const {
        // auto func = ReturnTarget->As<UserFunction>();
        // auto funcStart = func.Body;
        return nullptr;
    }
} // namespace pepper
