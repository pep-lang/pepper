

#include "Scope.h"

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Function.h"
#include "SemaContext.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    void Scope::function(Ref<Function> function, const std::string& name) {
        auto functionName = name.empty() ? function->name() : name;
        functions[functionName] = function;
    }

    Ref<Function> Scope::find_function(const std::string& name) const {
        auto it = functions.find(name);
        if (it != functions.end()) {
            return it->second;
        }
        return outer ? outer->find_function(name) : nullptr;
    }

    void Scope::symbol(const Address& value) {
        assert(!symbols.lookup(value.name));
        symbols[value.name] = value;
    }

    const Address& Scope::find_symbol(const std::string& identifier, bool localOnly) const {
        auto it = symbols.find(identifier);
        if (it != symbols.end())
            return it->second;
        return outer && !localOnly ? outer->find_symbol(identifier) : Address::null();
    }

    Ref<UserFunction> Scope::function_target() const {
        return func_target ? func_target : (outer ? outer->function_target() : nullptr);
    }

    Ref<llvm::IRBuilderBase> Scope::builder() const {
        return ir_builder ? ir_builder : (outer ? outer->builder() : nullptr);
    }

    //    Ref<llvm::IRBuilderBase> Scope::registers() const {
    //        auto func = functionTarget().as<UserFunction>();
    //        auto funcStart = func->Body->getFirstInsertionPt();
    //        auto builder = func->Builder;
    //        if (funcStart != func->Body->getInstList().begin()) {
    //            // skip past existing locals
    //            for (int localIdx = 0; localIdx < func->NumLocals; ++localIdx)
    //                ++funcStart;
    //            builder = Ref<llvm::IRBuilder<>>::create(func->Body);
    //            builder->SetInsertPoint(func->Body, funcStart);
    //        }
    //        ++func->NumLocals;
    //        return builder;
    //    }
} // namespace pepper
