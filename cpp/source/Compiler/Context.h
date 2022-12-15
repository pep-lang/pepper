
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

    class Context {
        static Context* Instance;

        llvm::Module* Module;
        Ref<Scope> Runtime;
        Ref<Scope> Globals;
        Ref<Scope> Locals;
        Ref<AST> Ast;

      public:
        static Context& get();

        Context(const std::string& moduleName);
        ~Context();

        llvm::Module* module() const {
            return Module;
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

        Scope* PushScope(llvm::IRBuilderBase* builder = nullptr);
        Scope* PopScope();
    };

} // namespace pepper
