
#pragma once

#include <memory>
#include <stack>
#include <string>
#include <unordered_map>

class IRBuilderBase;

class Scope {
    struct StackEntry {};

  public:
    Scope* Outer = nullptr;
    std::shared_ptr<IRBuilderBase> Builder = nullptr;
    std::unordered_map<std::string, class Type> Types;
    std::unordered_map<std::string, class Function> Functions;
    std::unordered_map<std::string, class Value> Locals;
    std::stack<StackEntry> Stack;
    std::shared_ptr<class UserFunction> ReturnTarget = nullptr;

    std::shared_ptr<IRBuilderBase> IR() const {
        return (Builder) ? Builder : Outer->Builder;
    }

    std::shared_ptr<IRBuilderBase> LocalRegisters() const;
};
