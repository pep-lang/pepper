
#pragma once

#include <memory>

namespace llvm {
    class Module;
}

class Scope;

class Context {
    static Context* Instance;
    static std::unique_ptr<Scope> Runtime;

    llvm::Module* Module;
    std::shared_ptr<Scope> Globals = nullptr;
    std::shared_ptr<Scope> Locals = nullptr;

  public:
    static Context& get() {
        if(!Instance) {
            Instance = new Context();
        }
        return *Instance;
    }

    Context(const std::string& moduleName);
    ~Context() = default;

    llvm::Module* module() const { return Module; }

    Scope* globals() const { return Globals.get(); }

    Scope* locals() const { return Locals.get(); }

    void injectRuntime();

    Scope* PushScope(llvm::IRBuilderBase* builder = nullptr);
    Scope* PopScope();
};
