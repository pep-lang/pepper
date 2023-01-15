
#include "CodeGenerator.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "CodeGenModule.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Frontend/Context.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Operations.h"
#include "Frontend/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Value.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<Scope> CodeGenerator::locals() {
        return Context::get().locals();
    }

    Ref<Scope> CodeGenerator::globals() {
        return Context::get().globals();
    }

    void CodeGenerator::pushFunction(Ref<UserFunction> function) {
        Context::get().pushFunction(function);
        auto sp = Module->getDebugInfo()->emitFunction(function.get());
        Module->getDebugInfo()->pushScope(sp);
    }

    void CodeGenerator::pushScope(const Ident& name) {
        Context::get().pushScope(name);
        // TODO: how to handle anonymous scopes
    }

    void CodeGenerator::popScope() {
        Module->getDebugInfo()->popScope();
        Context::get().popScope();
    }

    Address CodeGenerator::emit(Ref<SymbolRef> variableRef) {
        auto value = locals()->findSymbol(variableRef->Name);
        if (!value) {
            throw CompileError(variableRef->Source, "No symbol named {0} could be found", variableRef->Name);
        }
        return value;
    }

    Address CodeGenerator::emit(Ref<VariableDef> variableDef) {
        auto typeName = variableDef->Type;
        auto type = Types::get(typeName.toString());
        if (!type) {
            throw CompileError(variableDef->Source, "Unknown type {0}", typeName.toString());
        }

        auto value = Address(type, ir()->CreateAlloca(*type, nullptr, variableDef->Name), variableDef->Name);
        if (!variableDef->Hidden)
            Context::get().moduleContext()->getDebugInfo()->emitLocalVariable(value);
        locals()->newSymbol(value);

        if (auto defaultValue = maybeCodegen(variableDef->Default)) {
            auto typeOps = type->ops();
            typeOps->init(value, defaultValue);
        } else {
            ir()->CreateStore(zeroValue(type), value);
        }

        return value;
    }

    Address CodeGenerator::emit(Ref<StringLiteral> stringLiteral) {
        auto value = Address(Types::Int8->pointer(), ir()->CreateGlobalString(stringLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(Ref<IntegerLiteral> intLiteral) {
        auto type = Types::get(intLiteral->type().Name);
        auto value = Address(type, llvm::ConstantInt::get(*type, intLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(Ref<FloatLiteral> floatLiteral) {
        auto type = Types::get(floatLiteral->type().Name);
        auto value = Address(type, llvm::ConstantFP::get(*type, floatLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(Ref<BoolLiteral> boolLiteral) {
        auto value = Address(Types::Bool, llvm::ConstantInt::getBool(*Types::Bool, boolLiteral->Value));
        return value;
    }

    Address CodeGenerator::emit(Ref<PointerLiteral> pointerLiteral) {
        assert(pointerLiteral->Value == 0);
        auto type = Types::UInt8->pointer();
        auto value = Address(type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type->llvmType())));
        return value;
    }

    Address CodeGenerator::codegen(Ref<Node> node) {
        PEP_TRACE(TraceChannel::Codegen, indent(node->toString(), 2));
        Module->getDebugInfo()->setSourceLocation(node->Source);

        Address value;
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
        else if (node->is<ThisDef>())
            value = emit(node.as<ThisDef>());
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
        else if (node->is<ExternFunctionDef>())
            value = emit(node.as<ExternFunctionDef>());
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
        else if (node->is<None>())
            ;
        else
            throw InternalCompilerError("Unknown AST node");

        auto src = node->source();
        auto at = src.empty() ? "" : "@";
        std::string const output =
            llvm::formatv("{0} -> {1} {2}{3}", rpad(node->rtti()->name(), 20), rpad(toString(value), 80), at, src);
        PEP_TRACE(TraceChannel::Codegen, indent(output, 2));
        return value;
    }

    CodeGenerator::CodeGenerator(Ref<CodeGenModule> module) {
        Module = Context::get().moduleContext();
    }

    void CodeGenerator::generate(Ref<ast::AST> tree) {
        PEP_TRACE(TraceChannel::Codegen, "Code generation:");
        PEP_TRACE(TraceChannel::Codegen, "Instantiation pass:");
        for (const auto& root : tree->roots()) {
            try {
                if (root->is<StructDef>())
                    instantiate(root.as<StructDef>());
                else
                    instantiate(root.as<FunctionDef>());
            } catch (CompileError& ce) {
                Messages::Report<Error>(ce.what());
            } catch (InternalCompilerError& ice) {
                Messages::Report<Error>(ice.what());
            }
        }
        PEP_TRACE(TraceChannel::Codegen, "Codegen pass:")
        for (const auto& root : tree->roots()) {
            try {
                if (root->is<StructDef>())
                    codegenStruct(root.as<StructDef>());
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
