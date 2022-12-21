
#pragma once

#include "Core/Common.h"
#include <cassert>
#include <memory>
#include <string>

namespace llvm {
    class Module;
    class IRBuilderBase;
} // namespace llvm

namespace pepper {
    class AST;
    class Scope;
    class Executor;

    class Context {
        static Context* Instance;

        Ref<Executor> Exec;
        llvm::Module* Module;
        Ref<Scope> Runtime;
        Ref<Scope> Globals;
        Ref<Scope> Locals;
        Ref<AST> Ast;

      public:
        static Context& get();

        Context(const std::string& moduleName);
        ~Context();

        llvm::Module* module() const;

        Ref<Executor> executor() const {
            return Exec;
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
