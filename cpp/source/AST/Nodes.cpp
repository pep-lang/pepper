
#include "AST/Nodes.h"

#include "Codegen/Scope.h"
#include "Compiler/Context.h"
#include "Compiler/Type.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include <algorithm>

namespace pepper::ast {

    static llvm::FunctionType* functionTy(llvm::Type* returnType, const Params& args, bool vararg = false) {
        std::vector<llvm::Type*> argTypes;
        std::for_each(args.begin(), args.end(), [&](auto s) { argTypes.push_back(s.Type); });
        return llvm::FunctionType::get(returnType, argTypes, vararg);
    }

    FunctionNode::FunctionNode(llvm::Type* returnType, const std::string& name, const Params& params, bool vararg)
        : Symbol(functionTy(returnType, params, vararg), name)
        , ReturnType(returnType)
        , Parameters(params)
        , Vararg(vararg) {
    }

    llvm::Type* IntegerLiteral::type() const {
        return Types::Int64;
    }

    llvm::Type* FloatLiteral::type() const {
        return Types::Double;
    }

    llvm::Type* StringLiteral::type() const {
        return Types::Int8->getPointerTo(0);
    }
} // namespace pepper::ast
