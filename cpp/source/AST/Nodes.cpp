
#include "AST/Nodes.h"

#include "Compiler/Type.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper::ast {
    VariableRef::VariableRef(const std::string& name)
        : Identifier(name) {
    }

    static llvm::FunctionType* functionTy(llvm::Type* returnType, std::vector<Symbol> args, bool vararg = false) {
        std::vector<llvm::Type*> argTypes;
        std::for_each(args.begin(), args.end(), [&](auto s) {
            argTypes.push_back(s.type());
        });
        return llvm::FunctionType::get(returnType, argTypes, vararg);
    }

    FunctionNode::FunctionNode(Ref<Type> returnType,
                               const std::string& name,
                               const std::vector<Symbol>& params,
                               bool vararg)
        : Symbol(functionTy(*returnType, params, vararg), name)
        , ReturnType(returnType)
        , Params(params)
        , Vararg(vararg) {
    }

    FunctionCall::FunctionCall(Ref<FunctionDef> target, const std::vector<Ref<Expression>>& args)
        : Target(target)
        , Args(args) {
    }
} // namespace pepper::ast
