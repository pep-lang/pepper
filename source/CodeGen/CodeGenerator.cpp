
#include "CodeGenerator.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "CodeGenModule.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/Messages.h"
#include "Sema/Operations.h"
#include "Sema/SemaContext.h"
#include "Sema/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Value.h"

namespace pepper {
    Ref<Scope> CodeGenerator::locals() {
        return SemaContext::get().locals();
    }

    Ref<Scope> CodeGenerator::globals() {
        return SemaContext::get().globals();
    }

    void CodeGenerator::pushFunction(Ref<UserFunction> function) {
        SemaContext::get().pushFunction(function);
        auto sp = Module->getDebugInfo()->emitFunction(function.get());
        Module->getDebugInfo()->pushScope(sp);
    }

    void CodeGenerator::pushScope(const Ident& name) {
        SemaContext::get().pushScope(name);
        // TODO: how to handle anonymous scopes
    }

    void CodeGenerator::popScope() {
        Module->getDebugInfo()->popScope();
        SemaContext::get().popScope();
    }

    Address CodeGenerator::emit(const ast::SymbolRef* symbol) {
        auto value = locals()->findSymbol(symbol->Name);
        if (!value) {
            throw CompileError(symbol->Source, "No symbol named {0} could be found", symbol->Name);
        }
        return value;
    }

    Address CodeGenerator::emit(const ast::VariableDef* variableDef) {
        auto typeName = variableDef->Type;
        auto type = Types::get(typeName.toString());
        if (!type) {
            throw CompileError(variableDef->Source, "Unknown type {0}", typeName.toString());
        }

        auto value = Address(type, ir()->CreateAlloca(*type, nullptr, variableDef->Name), variableDef->Name);
        if (!variableDef->Hidden)
            Module->getDebugInfo()->emitLocalVariable(value);
        locals()->newSymbol(value);

        if (auto defaultValue = maybeCodegen(variableDef->Default)) {
            auto typeOps = type->ops();
            typeOps->init(value, defaultValue);
        } else {
            ir()->CreateStore(zeroValue(type), value);
        }

        return value;
    }

    Address CodeGenerator::emit(const ast::StringLiteral* stringLiteral) {
        auto value = Address(Types::Int8->pointer(), ir()->CreateGlobalString(stringLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(const ast::IntegerLiteral* intLiteral) {
        auto type = Types::get(intLiteral->type().Name);
        auto value = Address(type, llvm::ConstantInt::get(*type, intLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(const ast::FloatLiteral* floatLiteral) {
        auto type = Types::get(floatLiteral->type().Name);
        auto value = Address(type, llvm::ConstantFP::get(*type, floatLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(const ast::BoolLiteral* boolLiteral) {
        auto value = Address(Types::Bool, llvm::ConstantInt::getBool(*Types::Bool, boolLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(const ast::PointerLiteral* pointerLiteral) {
        assert(pointerLiteral->Value == 0);
        auto type = Types::UInt8->pointer();
        auto llvmType = Types::get(type.get());
        auto value = Address(type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(llvmType)));
        return value;
    }

    Address CodeGenerator::emit(const ast::Index* index) {
        auto lhs = codegen(index->LHS);
        auto idx = codegen(index->IndexExpr);
        auto lhsType = lhs.Ty;
        lhs = load(lhs);
        auto element = Address{
            lhs.Ty, ir()->CreateInBoundsGEP(*lhs.Ty, lhs, {llvm::ConstantInt::get(*Types::Int32, uint64_t(0)), idx})};
        return element;
    }

    Address CodeGenerator::codegen(const ast::Node* node) {
        Messages::Indent(TraceChannel::Codegen);
        PEP_TRACE(TraceChannel::Codegen, node->toString());
        Messages::Indent(TraceChannel::Codegen);
        Module->getDebugInfo()->setSourceLocation(node->Source);

        Address value;
        if (node->is<ast::BinaryOp>())
            value = emit(node->as<ast::BinaryOp>());
        else if (node->is<ast::UnaryOp>())
            value = emit(node->as<ast::UnaryOp>());
        else if (node->is<ast::Branch>())
            value = emit(node->as<ast::Branch>());
        else if (node->is<ast::Ternary>())
            value = emit(node->as<ast::Ternary>());
        else if (node->is<ast::While>())
            value = emit(node->as<ast::While>());
        else if (node->is<ast::ForRange>())
            value = emit(node->as<ast::ForRange>());
        else if (node->is<ast::ThisDef>())
            value = emit(node->as<ast::ThisDef>());
        else if (node->is<ast::FieldDef>())
            value = emit(node->as<ast::FieldDef>());
        else if (node->is<ast::VariableDef>())
            value = emit(node->as<ast::VariableDef>());
        else if (node->is<ast::ThisRef>())
            value = emit(node->as<ast::ThisRef>());
        else if (node->is<ast::MemberRef>())
            value = emit(node->as<ast::MemberRef>());
        else if (node->is<ast::SymbolRef>())
            value = emit(node->as<ast::SymbolRef>());
        else if (node->is<ast::ExternFunctionRef>())
            value = emit(node->as<ast::ExternFunctionRef>());
        else if (node->is<ast::FunctionDef>())
            value = emit(node->as<ast::FunctionDef>());
        else if (node->is<ast::Return>())
            value = emit(node->as<ast::Return>());
        else if (node->is<ast::MethodCall>())
            value = emit(node->as<ast::MethodCall>());
        else if (node->is<ast::FunctionCall>())
            value = emit(node->as<ast::FunctionCall>());
        else if (node->is<ast::PointerLiteral>())
            value = emit(node->as<ast::PointerLiteral>());
        else if (node->is<ast::StringLiteral>())
            value = emit(node->as<ast::StringLiteral>());
        else if (node->is<ast::FloatLiteral>())
            value = emit(node->as<ast::FloatLiteral>());
        else if (node->is<ast::IntegerLiteral>())
            value = emit(node->as<ast::IntegerLiteral>());
        else if (node->is<ast::BoolLiteral>())
            value = emit(node->as<ast::BoolLiteral>());
        else if (node->is<ast::Intrinsic>())
            value = emit(node->as<ast::Intrinsic>());
        else if (node->is<ast::Index>())
            value = emit(node->as<ast::Index>());
        else if (node->is<ast::None>())
            ;
        else
            throw InternalCompilerError("Unknown AST node");

        auto src = node->source();
        auto at = src.empty() ? "" : "@";
        PEP_TRACE(
            TraceChannel::Codegen,
            llvm::formatv("{0} -> {1} {2}{3}", rpad(node->rtti()->name(), 20), rpad(toString(value), 80), at, src));
        Messages::Outdent(TraceChannel::Codegen);
        Messages::Outdent(TraceChannel::Codegen);
        return value;
    }

    CodeGenerator::CodeGenerator(Ref<CodeGenModule> module) {
        Module = module;
    }

    void CodeGenerator::generate(Ref<ast::AST> tree) {
        PEP_TRACE(TraceChannel::Codegen, "Code generation:");
        PEP_TRACE(TraceChannel::Codegen, "Instantiation pass:");
        try {
            for (const auto& st : tree->structs())
                instantiate(st);
            for (const auto& st : tree->structs())
                instantiateMethods(st);
            for (const auto& fn : tree->externs())
                instantiate(fn);
            for (const auto& fn : tree->functions())
                instantiate(fn);
        } catch (CompileError& ce) {
            Messages::Report<Error>(ce.what());
        } catch (InternalCompilerError& ice) {
            Messages::Report<Error>(ice.what());
        }

        PEP_TRACE(TraceChannel::Codegen, "Codegen pass:")
        try {
            for (auto& st : tree->structs())
                codegenStruct(st);
            for (auto& fn : tree->functions())
                codegen(fn);
        } catch (CompileError& ce) {
            Messages::Report<Error>(ce.what());
        } catch (InternalCompilerError& ice) {
            Messages::Report<Error>(ice.what());
        }
    }
} // namespace pepper
