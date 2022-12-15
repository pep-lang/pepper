
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

    Context::Context(const std::string& moduleName)
        : Runtime(Ref<Scope>::create())
        , Globals(Ref<Scope>::create())
        , Locals(Globals)
        , Ast(Ref<AST>::create()) {
        assert(Instance == nullptr);
        Instance = this;
    }

    Context::~Context() {
        Instance = nullptr;
    }

} // namespace pepper
