
#include "Codegen.h"
#include <unordered_map>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Codegen/Context.h"
#include "Codegen/Function.h"
#include "Codegen/LLVMUtils.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Struct.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<llvm::IRBuilderBase> Codegen::ir() {
        return Context::get().locals()->builder();
    }

    Ref<llvm::IRBuilderBase> Codegen::registers() {
        return Context::get().locals()->registers();
    }

    using llvm::cast;
    using llvm::isa;

    llvm::Type* Codegen::resolveType(llvm::Value* value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto allocaInst = cast<llvm::AllocaInst>(value);
            return allocaInst->getAllocatedType();
        }
        if (isa<llvm::GetElementPtrInst>(value)) {
            auto gepInst = cast<llvm::GetElementPtrInst>(value);
            return gepInst->getResultElementType();
        }
        return value->getType();
    }

    llvm::Value* Codegen::read(llvm::Value* value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto type = resolveType(value);
            return ir()->CreateLoad(type, value);
        }
        if (isa<llvm::GetElementPtrInst>(value)) {
            auto type = resolveType(value);
            return ir()->CreateLoad(type, value);
        }
        return value;
    }

    llvm::Value* Codegen::zeroValue(llvm::Type* type) {
        if (type->isIntegerTy())
            return llvm::ConstantInt::get(type, 0);
        if (type->isFloatingPointTy())
            return llvm::ConstantFP::get(type, 0.0f);
        if (type->isPointerTy())
            return llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type));
        throw InternalCompilerError("No known default value for type {0}", Types::toString(type));
    }

    llvm::Value* Codegen::emit(Ref<VariableRef> variableRef) {
        auto value = Context::get().locals()->findSymbol(variableRef->identifier());
        return value;
    }

    llvm::Value* Codegen::emit(Ref<VariableDef> variableDef) {
        auto typeName = variableDef->type();
        auto type = Types::get(typeName);
        auto value = registers()->CreateAlloca(*type, nullptr, variableDef->identifier());

        auto defaultValue = maybeCodegen(variableDef->defaultValue());
        if (!defaultValue)
            defaultValue = zeroValue(*type);

        auto typeOps = TypeOps::get(*type);
        auto coercedValue = typeOps->coerce(defaultValue);
        ir()->CreateStore(coercedValue, value);
        Context::get().locals()->newSymbol(variableDef->identifier(), value);
        return value;
    }

    llvm::Value* Codegen::emit(Ref<StringLiteral> stringLiteral) {
        auto value = ir()->CreateGlobalString(stringLiteral->value());
        return value;
    }

    llvm::Value* Codegen::emit(Ref<IntegerLiteral> intLiteral) {
        auto value = llvm::ConstantInt::get(*Types::Int64, intLiteral->value());
        return value;
    }

    llvm::Value* Codegen::emit(Ref<FloatLiteral> floatLiteral) {
        auto value = llvm::ConstantFP::get(*Types::Double, floatLiteral->value());
        return value;
    }

    llvm::Value* Codegen::codegen(Ref<Node> node) {
        llvm::Value* value = nullptr;
        if (node->is<BinaryOp>())
            value = emit(node.as<BinaryOp>());
        else if (node->is<FieldDef>())
            value = emit(node.as<FieldDef>());
        else if (node->is<VariableDef>())
            value = emit(node.as<VariableDef>());
        else if (node->is<ThisRef>())
            value = emit(node.as<ThisRef>());
        else if (node->is<MemberRef>())
            value = emit(node.as<MemberRef>());
        else if (node->is<VariableRef>())
            value = emit(node.as<VariableRef>());
        else if (node->is<FunctionDef>())
            value = emit(node.as<FunctionDef>());
        else if (node->is<Return>())
            value = emit(node.as<Return>());
        else if (node->is<FunctionCall>())
            value = emit(node.as<FunctionCall>());
        else if (node->is<StringLiteral>())
            value = emit(node.as<StringLiteral>());
        else if (node->is<FloatLiteral>())
            value = emit(node.as<FloatLiteral>());
        else if (node->is<IntegerLiteral>())
            value = emit(node.as<IntegerLiteral>());
        if (value) {
            PEP_TRACE(TraceChannel::Codegen, "{0} -> {1}", node->toString(), toString(value));
            return value;
        }
        throw InternalCompilerError("Unknown AST node");
    }

    Codegen::Codegen(const Name& moduleName, Ref<ast::AST> tree)
        : Tree(tree) {
        Ctx = Ref<Context>::New(moduleName);
        Module = Ctx->moduleContext();
    }

    Ref<ModuleContext> Codegen::emit() {
        for (auto root : Tree->roots()) {
            try {
                if (root->is<StructDef>())
                    emit(root.as<StructDef>());
                else
                    codegen(root);
            } catch (CompileError ce) {
                Messages::Report<Error>(ce.what());
            } catch (InternalCompilerError ice) {
                Messages::Report<Error>(ice.what());
                return nullptr;
            }
        }
        return Context::get().moduleContext();
    }
} // namespace pepper
