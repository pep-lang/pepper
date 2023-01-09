
#include "Codegen.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Frontend/Context.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/ModuleContext.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<llvm::IRBuilderBase> Codegen::ir() {
        return Context::get().locals()->builder();
    }

    Ref<Scope> Codegen::locals() {
        return Context::get().locals();
    }

    Ref<Scope> Codegen::globals() {
        return Context::get().globals();
    }

    void Codegen::pushFunction(Ref<UserFunction> function) {
        Context::get().pushFunction(function);
    }

    void Codegen::pushScope(const Ident& name) {
        Context::get().pushScope(name);
    }

    void Codegen::popScope() {
        Context::get().popScope();
    }

    using llvm::cast;
    using llvm::isa;

    llvm::Type* Codegen::resolveType(Value value) {
        if (isa<llvm::AllocaInst>(*value.V)) {
            auto allocaInst = cast<llvm::AllocaInst>(value.V);
            return allocaInst->getAllocatedType();
        }
        if (isa<llvm::GetElementPtrInst>(*value.V)) {
            auto gepInst = cast<llvm::GetElementPtrInst>(value.V);
            return gepInst->getResultElementType();
        }
        return value->getType();
    }

    Value Codegen::read(Value value) {
        if (isa<llvm::AllocaInst>(*value.V)) {
            auto type = resolveType(value);
            return Value{value.Ty, ir()->CreateLoad(type, value)};
        }
        if (isa<llvm::GetElementPtrInst>(*value.V)) {
            auto type = resolveType(value);
            return Value{value.Ty, ir()->CreateLoad(type, value)};
        }
        return value;
    }

    Value Codegen::zeroValue(Ref<TypeInfo> type) {
        if (type->llvmType()->isIntegerTy())
            return Value{type, llvm::ConstantInt::get(*type, 0)};
        if (type->llvmType()->isFloatingPointTy())
            return Value{type, llvm::ConstantFP::get(*type, 0.0f)};
        if (type->llvmType()->isPointerTy())
            return Value{type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type->llvmType()))};
        throw InternalCompilerError("No known default value for type {0}", Types::toString(type));
    }

    Value Codegen::emit(Ref<SymbolRef> variableRef) {
        auto value = locals()->findSymbol(variableRef->identifier());
        if (!value) {
            throw CompileError(variableRef->Source, "No symbol named {0} could be found", variableRef->identifier());
        }
        return value;
    }

    Value Codegen::emit(Ref<VariableDef> variableDef) {
        auto typeName = variableDef->Type;
        auto type = Types::get(typeName.toString());
        if (!type) {
            throw CompileError(variableDef->Source, "Unknown type {0}", typeName.toString());
        }
        auto value = Value(type, ir()->CreateAlloca(*type, nullptr, variableDef->Name), variableDef->Name);

        auto defaultValue = maybeCodegen(variableDef->Default);
        if (!defaultValue)
            defaultValue = zeroValue(type);

        auto typeOps = type->ops();
        auto coercedValue = typeOps->coerce(defaultValue);
        ir()->CreateStore(coercedValue, value);
        locals()->newSymbol(value);
        return value;
    }

    Value Codegen::emit(Ref<StringLiteral> stringLiteral) {
        auto value = Value(Types::Int8->pointer(), ir()->CreateGlobalString(stringLiteral->Value));
        return value;
    }

    Value Codegen::emit(Ref<IntegerLiteral> intLiteral) {
        auto value = Value(Types::Int64, llvm::ConstantInt::get(*Types::Int64, intLiteral->Value));
        return value;
    }

    Value Codegen::emit(Ref<FloatLiteral> floatLiteral) {
        auto value = Value(Types::Double, llvm::ConstantFP::get(*Types::Double, floatLiteral->Value));
        return value;
    }

    Value Codegen::emit(Ref<BoolLiteral> boolLiteral) {
        auto value = Value(Types::Bool, llvm::ConstantInt::getBool(*Types::Bool, boolLiteral->Value));
        return value;
    }

    Value Codegen::emit(Ref<PointerLiteral> pointerLiteral) {
        assert(pointerLiteral->Value == 0);
        auto type = Types::UInt8->pointer();
        auto value = Value(type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type->llvmType())));
        return value;
    }

    Value Codegen::codegen(Ref<Node> node) {
        Value value;
        if (node->is<BinaryOp>())
            value = emit(node.as<BinaryOp>());
        else if (node->is<UnaryOp>())
            value = emit(node.as<UnaryOp>());
        else if (node->is<Branch>())
            value = emit(node.as<Branch>());
        else if (node->is<Ternary>())
            value = emit(node.as<Ternary>());
        else if (node->is<While>())
            value = emit(node.as<While>());
        else if (node->is<ForRange>())
            value = emit(node.as<ForRange>());
        else if (node->is<FieldDef>())
            value = emit(node.as<FieldDef>());
        else if (node->is<VariableDef>())
            value = emit(node.as<VariableDef>());
        else if (node->is<ThisRef>())
            value = emit(node.as<ThisRef>());
        else if (node->is<MemberRef>())
            value = emit(node.as<MemberRef>());
        else if (node->is<SymbolRef>())
            value = emit(node.as<SymbolRef>());
        else if (node->is<FunctionDef>())
            value = emit(node.as<FunctionDef>());
        else if (node->is<Return>())
            value = emit(node.as<Return>());
        else if (node->is<MethodCall>())
            value = emit(node.as<MethodCall>());
        else if (node->is<FunctionCall>())
            value = emit(node.as<FunctionCall>());
        else if (node->is<PointerLiteral>())
            value = emit(node.as<PointerLiteral>());
        else if (node->is<StringLiteral>())
            value = emit(node.as<StringLiteral>());
        else if (node->is<FloatLiteral>())
            value = emit(node.as<FloatLiteral>());
        else if (node->is<IntegerLiteral>())
            value = emit(node.as<IntegerLiteral>());
        else if (node->is<BoolLiteral>())
            value = emit(node.as<BoolLiteral>());
        else
            throw InternalCompilerError("Unknown AST node");

        auto src = node->source();
        auto at = src.empty() ? "" : "@";
        std::string const output =
            llvm::formatv("{0} -> {1} {2}{3}", rpad(node->rtti()->name(), 20), rpad(toString(value), 80), at, src);
        PEP_TRACE(TraceChannel::Codegen, indent(output, 2));
        return value;
    }

    Codegen::Codegen(Ref<ModuleContext> module) {
        Module = Context::get().moduleContext();
    }

    void Codegen::generate(Ref<ast::AST> tree) {
        PEP_TRACE(TraceChannel::Codegen, "Code generation:")
        for (const auto& root : tree->roots()) {
            try {
                if (root->is<StructDef>())
                    emit(root.as<StructDef>());
                else
                    codegen(root);
            } catch (CompileError& ce) {
                Messages::Report<Error>(ce.what());
            } catch (InternalCompilerError& ice) {
                Messages::Report<Error>(ice.what());
            }
        }
    }
} // namespace pepper
