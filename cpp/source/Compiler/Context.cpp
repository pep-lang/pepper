
#include "Compiler/Context.h"

#include "AST/AST.h"
#include "Compiler/Scope.h"
#include <cassert>

namespace pepper {
    Context* Context::Instance = nullptr;

    Context& Context::get() {
        assert(Instance);
        return *Instance;
    }

    Context::Context(const std::string& moduleName) {
        assert(Instance == nullptr);
        Instance = this;

        Globals = Ref<Scope>::create();
        Locals = Globals;
        Ast = Ref<AST>::create();
    }

    Context::~Context() {
        Instance = nullptr;
    }

} // namespace pepper
