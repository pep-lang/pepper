
#include "AST/Nodes.h"

#include "Compiler/Type.h"

namespace pepper::ast {
    VariableRef::VariableRef(const std::string& name)
        : Identifier(name) {
    }

    FunctionNode::FunctionNode(Ref<Type> returnType,
                               const std::string& name,
                               const std::vector<Symbol>& params,
                               bool varargs)
        : Symbol(FunctionType::Create(returnType, params, varargs).as<Type>(), name)
        , ReturnType(returnType)
        , Params(params)
        , Varargs(varargs) {
    }
} // namespace pepper::ast
