
#include "Compiler/Context.h"

#include "AST/AST.h"
#include "Compiler/Executor.h"
#include "Compiler/Scope.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include <cassert>

namespace pepper {
    Context* Context::Instance = nullptr;

    Context& Context::get() {
        assert(Instance);
        return *Instance;
    }

    Context::Context(const std::string& moduleName)
        : Runtime(Ref<Scope>::create())
        , Globals(Ref<Scope>::create())
        , Locals(Globals)
        , Ast(Ref<AST>::create()) {
        assert(Instance == nullptr);
        Instance = this;

        Exec = Executor::Create();
        Module = Exec->createModule(moduleName);
    }

    Context::~Context() {
        Instance = nullptr;
    }

    llvm::Module* Context::module() const {
        return Module;
    }

} // namespace pepper
