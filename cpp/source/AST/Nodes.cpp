
#include "AST/Nodes.h"

#include "Compiler/Type.h"

namespace pepper::ast {
    VariableRef::VariableRef(const std::string& name)
        : Identifier(name) {
    }

    FunctionNode::FunctionNode(Ref<Type> returnType,
                               const std::string& name,
                               const std::vector<Symbol>& params,
                               bool vararg)
        : Symbol(FunctionType::Create(returnType, params, vararg).as<Type>(), name)
        , ReturnType(returnType)
        , Params(params)
        , Vararg(vararg) {
    }

    FunctionCall::FunctionCall(Ref<FunctionDef> target, const std::vector<Ref<Expression>>& args)
        : Target(target)
        , Args(args) {
    }
} // namespace pepper::ast
