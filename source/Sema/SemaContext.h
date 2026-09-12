
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "Scope.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    class Types;
    class UserFunction;

    class SemaContext {
        static SemaContext* Instance;

        std::unique_ptr<llvm::LLVMContext> llvm_context;
        Ref<Types> type_map;
        Ref<Scope> global_scope;
        Ref<Scope> local_scope;
        bool is_unit_test = false;

      public:
        static SemaContext& get();
        static Ref<llvm::IRBuilderBase> ir();

        explicit SemaContext();
        ~SemaContext();

        [[nodiscard]] Ref<Types> types() const {
            return type_map;
        }

        [[nodiscard]] Ref<Scope> globals() const {
            return global_scope;
        }

        [[nodiscard]] Ref<Scope> locals() const {
            return local_scope;
        }

        llvm::LLVMContext& get_llvm_context() {
            return *llvm_context;
        }

        std::unique_ptr<llvm::LLVMContext>&& take_llvm_context() {
            local_scope.reset();
            global_scope.reset();
            type_map.reset();
            Instance = nullptr;
            return std::move(llvm_context);
        }

        void push_function(Ref<UserFunction> function);
        void push_scope(const std::string& name, Ref<llvm::IRBuilderBase> builder = nullptr);
        void pop_scope();
    };

} // namespace pepper
