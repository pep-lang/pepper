
#pragma once

#include <memory>
#include <stack>
#include <string>
#include <unordered_map>

namespace llvm {
    class IRBuilderBase;
}

class Scope {
    struct StackEntry {};

  public:
    Scope* Outer = nullptr;
    std::shared_ptr<llvm::IRBuilderBase> Builder = nullptr;
    std::unordered_map<std::string, class Type> Types;
    std::unordered_map<std::string, class Function> Functions;
    std::unordered_map<std::string, class Value> Locals;
    std::stack<StackEntry> Stack;
    std::shared_ptr<class UserFunction> ReturnTarget = nullptr;

    std::shared_ptr<llvm::IRBuilderBase> ir() const { return (Builder) ? Builder : Outer->Builder; }

    std::shared_ptr<llvm::IRBuilderBase> localRegisters() const;
};
