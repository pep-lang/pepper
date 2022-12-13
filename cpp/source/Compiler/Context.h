
#pragma once

#include <cassert>
#include <memory>
#include <string>

namespace llvm {
    class Module;
    class IRBuilderBase;
} // namespace llvm

class Scope;

class Context {
    static Context* Instance;
    static std::unique_ptr<Scope> Runtime;

    llvm::Module* Module;
    std::shared_ptr<Scope> Globals = nullptr;
    std::shared_ptr<Scope> Locals = nullptr;

  public:
    static Context& get();

    Context(const std::string& moduleName);
    ~Context();

    llvm::Module* module() const { return Module; }

    Scope* globals() const { return Globals.get(); }

    Scope* locals() const { return Locals.get(); }

    void injectRuntime();

    Scope* PushScope(llvm::IRBuilderBase* builder = nullptr);
    Scope* PopScope();
};
