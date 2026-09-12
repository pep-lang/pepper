
#include <cassert>

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Function.h"
#include "Scope.h"
#include "SemaContext.h"
#include "Types.h"

namespace pepper {
    SemaContext* SemaContext::Instance = nullptr;

    SemaContext& SemaContext::get() {
        assert(Instance);
        return *Instance;
    }

    Ref<llvm::IRBuilderBase> SemaContext::ir() {
        return get().locals()->builder();
    }

    SemaContext::SemaContext() {
        assert(Instance == nullptr);
        Instance = this;

        llvm_context = std::make_unique<llvm::LLVMContext>();

        type_map = Ref<Types>::create(*llvm_context);

        // Builtins = Ref<Runtime>::create(Module);
        global_scope = Ref<Scope>::create("Globals");
        local_scope = global_scope;
    }

    SemaContext::~SemaContext() {
        Instance = nullptr;
    }

    void SemaContext::push_function(Ref<UserFunction> function) {
        push_scope(function->name(), function->ir_builder);
        local_scope->func_target = function;
        if (function->is<Method>()) {
            local_scope->this_struct = function.as<Method>()->This;
        }
    }

    void SemaContext::push_scope(const std::string& name, Ref<llvm::IRBuilderBase> builder) {
        local_scope = Ref<Scope>::create(name, local_scope);
        local_scope->ir_builder = builder;
    }

    void SemaContext::pop_scope() {
        local_scope = local_scope->outer == global_scope ? global_scope : local_scope->outer;
    }

} // namespace pepper
