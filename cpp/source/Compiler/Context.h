
#pragma once

#include "Core/Common.h"
#include <cassert>
#include <memory>
#include <string>

namespace llvm {
    class LLVMContext;
    class Module;
    class IRBuilderBase;
} // namespace llvm

namespace pepper {
    class AST;
    class Scope;
    class Executor;
    class Types;

    class Context {
        static Context* Instance;

        Ref<Executor> Exec;
        std::unique_ptr<llvm::LLVMContext> Ctx;
        std::unique_ptr<llvm::Module> Module;
        Ref<Types> TypeMap;
        Ref<Scope> Runtime;
        Ref<Scope> Globals;
        Ref<Scope> Locals;
        Ref<AST> Ast;

      public:
        static Context& get();

        Context(const std::string& moduleName);
        ~Context();

        llvm::Module* module() const;

        std::unique_ptr<llvm::Module>&& takeModule() {
            return std::move(Module);
        }

        std::unique_ptr<llvm::LLVMContext>&& takeContext() {
            return std::move(Ctx);
        }

        Ref<Executor> executor() const {
            return Exec;
        }

        Ref<Types> types() const {
            return TypeMap;
        }

        Scope* globals() const {
            return Globals.get();
        }

        Scope* locals() const {
            return Locals.get();
        }

        Ref<AST> ast() const {
            return Ast;
        }

        Ref<Scope> runtime() const {
            return Runtime;
        }

        void injectRuntime();

        Scope* pushScope(llvm::IRBuilderBase* builder = nullptr);
        Scope* popScope();
    };

} // namespace pepper
