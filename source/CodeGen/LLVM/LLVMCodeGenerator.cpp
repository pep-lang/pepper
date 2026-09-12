
#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include <filesystem>

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/Messages.h"
#include "Sema/Model/Module.h"
#include "Sema/Model/Nodes.h"
#include "Sema/Operations.h"
#include "Sema/SemaContext.h"
#include "Sema/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Value.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"

namespace pepper {
    Ref<Scope> LLVMCodeGenerator::locals() {
        return SemaContext::get().locals();
    }

    Ref<Scope> LLVMCodeGenerator::globals() {
        return SemaContext::get().globals();
    }

    void LLVMCodeGenerator::push_function(Ref<UserFunction> function) {
        SemaContext::get().push_function(function);
        auto sp = module->get_debug_info()->emitFunction(function.get());
        module->get_debug_info()->push_scope(sp);
    }

    void LLVMCodeGenerator::push_scope(const Ident& name) {
        SemaContext::get().push_scope(name);
        // TODO: how to handle anonymous scopes
    }

    void LLVMCodeGenerator::pop_scope() {
        module->get_debug_info()->pop_scope();
        SemaContext::get().pop_scope();
    }

    Address LLVMCodeGenerator::emit(const sema::SymbolRef* symbol) {
        auto value = locals()->find_symbol(symbol->id);
        if (!value) {
            throw CompileError(symbol->source_loc, "No symbol named {0} could be found", symbol->id);
        }
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::VariableDef* variableDef) {
        auto typeName = variableDef->type;
        auto type = Types::get(typeName.to_string());
        if (!type) {
            throw CompileError(variableDef->source_loc, "Unknown type {0}", typeName.to_string());
        }

        auto value = Address(type, ir()->CreateAlloca(*type, nullptr, variableDef->name), variableDef->name);
        if (!variableDef->is_hidden)
            module->get_debug_info()->emitLocalVariable(value);
        locals()->symbol(value);

        if (auto defaultValue = maybeCodegen(variableDef->default_value)) {
            auto typeOps = type->ops();
            typeOps->init(value, defaultValue);
        } else {
            ir()->CreateStore(zero_value(type), value);
        }

        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::StringLiteral* stringLiteral) {
        auto value = Address(Types::Int8->pointer(), ir()->CreateGlobalString(stringLiteral->value));
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::IntegerLiteral* intLiteral) {
        auto type = Types::get(intLiteral->type().name);
        auto value = Address(type, llvm::ConstantInt::get(*type, intLiteral->value));
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::FloatLiteral* floatLiteral) {
        auto type = Types::get(floatLiteral->type().name);
        auto value = Address(type, llvm::ConstantFP::get(*type, floatLiteral->value));
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::BoolLiteral* boolLiteral) {
        auto value = Address(Types::Bool, llvm::ConstantInt::getBool(*Types::Bool, boolLiteral->value));
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::PointerLiteral* pointerLiteral) {
        assert(pointerLiteral->value == 0);
        auto type = Types::UInt8->pointer();
        auto llvmType = Types::get(type.get());
        auto value = Address(type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(llvmType)));
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::Index* index) {
        auto lhs = codegen(index->lhs);
        auto idx = codegen(index->expr);
        return lhs.type->ops()->add(lhs, idx);
    }

    Address LLVMCodeGenerator::codegen(const sema::Node* node) {
        Messages::indent(TraceChannel::Codegen);
        PEP_TRACE(TraceChannel::Codegen, node->to_string());
        Messages::indent(TraceChannel::Codegen);

        assert(node->source_loc.line != 0);

        module->get_debug_info()->setSourceLocation(node->source_loc);
        CompileError::Source = node->source_loc;

        Address value;
        if (node->is<sema::BinaryOp>())
            value = emit(node->as<sema::BinaryOp>());
        else if (node->is<sema::UnaryOp>())
            value = emit(node->as<sema::UnaryOp>());
        else if (node->is<sema::Branch>())
            value = emit(node->as<sema::Branch>());
        else if (node->is<sema::Ternary>())
            value = emit(node->as<sema::Ternary>());
        else if (node->is<sema::While>())
            value = emit(node->as<sema::While>());
        else if (node->is<sema::ForRange>())
            value = emit(node->as<sema::ForRange>());
        else if (node->is<sema::ThisDef>())
            value = emit(node->as<sema::ThisDef>());
        else if (node->is<sema::FieldDef>())
            value = emit(node->as<sema::FieldDef>());
        else if (node->is<sema::VariableDef>())
            value = emit(node->as<sema::VariableDef>());
        else if (node->is<sema::ThisRef>())
            value = emit(node->as<sema::ThisRef>());
        else if (node->is<sema::MemberRef>())
            value = emit(node->as<sema::MemberRef>());
        else if (node->is<sema::SymbolRef>())
            value = emit(node->as<sema::SymbolRef>());
        else if (node->is<sema::ExternFunctionRef>())
            value = emit(node->as<sema::ExternFunctionRef>());
        else if (node->is<sema::FunctionDef>())
            value = emit(node->as<sema::FunctionDef>());
        else if (node->is<sema::Return>())
            value = emit(node->as<sema::Return>());
        else if (node->is<sema::MethodCall>())
            value = emit(node->as<sema::MethodCall>());
        else if (node->is<sema::FunctionCall>())
            value = emit(node->as<sema::FunctionCall>());
        else if (node->is<sema::PointerLiteral>())
            value = emit(node->as<sema::PointerLiteral>());
        else if (node->is<sema::StringLiteral>())
            value = emit(node->as<sema::StringLiteral>());
        else if (node->is<sema::FloatLiteral>())
            value = emit(node->as<sema::FloatLiteral>());
        else if (node->is<sema::IntegerLiteral>())
            value = emit(node->as<sema::IntegerLiteral>());
        else if (node->is<sema::BoolLiteral>())
            value = emit(node->as<sema::BoolLiteral>());
        else if (node->is<sema::Intrinsic>())
            value = emit(node->as<sema::Intrinsic>());
        else if (node->is<sema::Index>())
            value = emit(node->as<sema::Index>());
        else if (node->is<sema::None>())
            ;
        else
            throw InternalCompilerError("Unknown AST node: {0}", node->rtti()->name());

        auto src = node->source();
        auto at = src.empty() ? "" : "@";
        PEP_TRACE(
            TraceChannel::Codegen,
            llvm::formatv("{0} -> {1} {2}{3}", rpad(node->rtti()->name(), 20), rpad(to_string(value), 80), at, src));
        Messages::outdent(TraceChannel::Codegen);
        Messages::outdent(TraceChannel::Codegen);
        return value;
    }

    static std::string module_filename(const llvm::Module& module) {
        const auto& moduleSource = module.getSourceFileName();
        if (!moduleSource.empty()) {
            return std::filesystem::path(moduleSource).filename().replace_extension().string();
        }
        return module.getModuleIdentifier();
    }

    static std::string emit_obj_file(llvm::Module& module, Ref<Options> options) {
        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        auto cpu = "generic";
        auto cpuFeatures = "";

        std::string error;
        auto target = llvm::TargetRegistry::lookupTarget(targetTriple, error);

        // Print an error and exit if we couldn't find the requested target.
        // This generally occurs if we've forgotten to initialise the
        // TargetRegistry or we have a bogus target triple.
        if (!target) {
            throw InternalCompilerError("Failed to find requested target triple: {0}", targetTriple);
        }

        llvm::TargetOptions opt;
        auto rm = std::optional<llvm::Reloc::Model>();
        auto targetMachine = target->createTargetMachine(targetTriple, cpu, cpuFeatures, opt, rm);

        std::filesystem::path outputFile(options->build_dir);
        std::filesystem::path inputFile(module_filename(module));
        outputFile /= inputFile.filename().string() + ".o";

        auto object_file_path = outputFile.string();

        std::error_code errCode;
        llvm::raw_fd_ostream dest(object_file_path, errCode, llvm::sys::fs::OF_None);

        if (errCode) {
            throw CompileError("Could not open file: {0}", errCode.message());
        }

        llvm::legacy::PassManager pass;
        auto fileType = llvm::CGFT_ObjectFile;

        if (targetMachine->addPassesToEmitFile(pass, dest, nullptr, fileType)) {
            throw CompileError("TargetMachine can't emit a file of this type");
        }

        pass.run(module);
        dest.flush();

        PEP_VERBOSE("Object file written to {0}", outputFile.string());

        return object_file_path;
    }

    static void emit_ir(const llvm::Module& module, Ref<Options> options) {
        std::filesystem::path outputPath(options->build_dir);
        std::filesystem::path sourceFile(module_filename(module));
        outputPath /= sourceFile.filename().replace_extension(".ll");

        std::error_code EC;
        llvm::raw_fd_ostream out(outputPath.string(), EC);
        if (EC) {
            throw CompileError("Unable to write to {0}: {1}", outputPath.string(), EC.message());
        }

        module.print(out, nullptr, false, false);
        llvm::outs() << llvm::formatv("LLVM IR written to {0}\n", outputPath.string());
    }

    LLVMCodeGenerator::LLVMCodeGenerator(Ref<LLVMModuleGenerator> module_gen) {
        module = module_gen;
    }

    void LLVMCodeGenerator::generate(Ref<sema::Module> tree, Ref<Options> options) {
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
            Messages::report<Error>(ce.what());
        } catch (InternalCompilerError& ice) {
            Messages::report<Error>(ice.what());
        }

        PEP_TRACE(TraceChannel::Codegen, "Codegen pass:")
        try {
            for (auto& st : tree->structs())
                codegenStruct(st);
            for (auto& fn : tree->functions())
                codegen(fn);
        } catch (CompileError& ce) {
            Messages::report<Error>(ce.what());
        } catch (InternalCompilerError& ice) {
            Messages::report<Error>(ice.what());
        }

        if (PEP_TRACING(TraceChannel::IR)) {
            PEP_TRACE(TraceChannel::IR, "LLVM IR:");
            PEP_TRACE(TraceChannel::IR, module->to_string());
        }

        if (options->emit_llvm) {
            emit_ir(module->get_llvm_module(), options);
        }

        if (auto err = module->verify()) {
            throw CompileError("Module Verification failed: {0}", llvm::toString(std::move(err)));
        }

        object_file_path = emit_obj_file(module->get_llvm_module(), options);
    }

    std::string LLVMCodeGenerator::get_object_file_path() const {
        return object_file_path;
    }

} // namespace pepper
