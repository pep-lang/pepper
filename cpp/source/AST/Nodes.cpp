
#include "AST/Nodes.h"

#include "Codegen/Scope.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
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

    llvm::Type* BinaryOp::operandType(llvm::Type* lhsType, llvm::Type* rhsType) const {
        if (lhsType->isIntegerTy() && rhsType->isIntegerTy()) {
            return lhsType->getIntegerBitWidth() > rhsType->getIntegerBitWidth() ? lhsType : rhsType;
        }
        if (lhsType->isFloatingPointTy() || rhsType->isFloatingPointTy()) {
            auto bits = std::max(lhsType->getPrimitiveSizeInBits(), rhsType->getPrimitiveSizeInBits());
            return (bits > 32) ? Types::Double : Types::Float;
        }
        throw CompileError("Unable to determine operand type between lhs={0} rhs={1}",
                           Types::toString(lhsType),
                           Types::toString(rhsType));
    }
} // namespace pepper::ast
