
#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>
#include <iostream>

#include "AST/AST.h"
#include "AST/Transforms/Transform.h"
#include "CodeGen/CodeGenModule.h"
#include "CodeGen/CodeGenerator.h"
#include "Compiler/ImportResolver.h"
#include "Compiler/Linker.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Frontend/PepContext.h"
#include "Parser/Parser.h"
#include "llvm/ADT/Optional.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"

namespace pepper {
    class PepperCompiler : public Compiler {
        Ref<Options> Opts;

        // Re-used internals per module
        std::string ModuleName;
        std::unique_ptr<PepContext> Context;

        // Collected obj files for linking
        Vector<std::string> ObjFiles;

      public:
        explicit PepperCompiler(Ref<Options> options)
            : Opts(options)
            , ModuleName(options->ExeName) {
            llvm::InitializeNativeTarget();
            llvm::InitializeNativeTargetAsmPrinter();
            llvm::InitializeNativeTargetAsmParser();

            if (Opts->Verbose)
                Messages::EnableVerbose();
            if (Opts->TraceChannels)
                Messages::SetTraceChannels(Opts->TraceChannels);

            Context = std::make_unique<PepContext>();
        }

        Ref<CodeGenModule> compile() override {
            ensureBuildDirExists();

            Ref<ast::AST> parseTree = Ref<ast::AST>::New();
            ImportResolver importer(Opts->ImportPaths);

            llvm::StringSet seenFiles;
            auto sourceFiles = Opts->SourceFiles;
            seenFiles.insert(sourceFiles.begin(), sourceFiles.end());

            auto collectImports = [&](const std::string& sourceFile, Ref<ast::AST> ast) {
                const auto& importNodes = ast->imports();
                for (const auto& import : importNodes) {
                    auto importPath = importer.resolve(sourceFile, import->Module, import->Local);
                    if (importPath.empty())
                        throw CompileError(import->Source, "Cannot resolve import {0}", import->Module);
                    if (!seenFiles.contains(importPath)) {
                        sourceFiles.emplace_back(importPath);
                        seenFiles.insert(llvm::StringRef{importPath});
                    }
                }
            };

            if (Opts->InputStream) {
                PEP_TRACE(TraceChannel::Parser, "Parsing InputStream");
                auto ast = parse(*Opts->InputStream, ModuleName);
                parseTree->merge(ast);
                collectImports(ModuleName, ast);
            }

            while (!sourceFiles.empty()) {
                const auto& sourceFile = sourceFiles.pop_back_val();
                std::ifstream sourceStream(sourceFile, std::ios_base::in);
                PEP_TRACE(TraceChannel::Parser, "Parsing {0}...", sourceFile);
                auto ast = parse(sourceStream, sourceFile);
                parseTree->merge(ast);

                // Resolve all imports and add them to the list to process if necessary
                collectImports(sourceFile, ast);
            }

            ast::TransformPass transform(parseTree);
            parseTree = transform.run();

            if (PEP_TRACING(TraceChannel::AST)) {
                PEP_TRACE(TraceChannel::AST, "Parse tree:");
                parseTree->dump();
            }

            return codegen(parseTree);
        }

        Ref<ast::AST> parse(std::istream& sourceStream, const std::string& sourcePath) {
            Parser parser;
            auto ast = parser.parse(sourceStream, sourcePath);
            if (!ast || !Messages::errors().empty()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            return ast;
        }

        Ref<CodeGenModule> codegen(Ref<ast::AST> parseTree) {
            auto module = Ref<CodeGenModule>::New(*Context, ModuleName, Opts->PrimarySourceFile);
            CodeGenerator codeGen(module);
            codeGen.generate(parseTree);

            if (!Messages::errors().empty()) {
                Query(Messages::errors()).each([](auto e) { llvm::errs() << e.message() << "\n"; });
                throw CompileError("Error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::IR)) {
                PEP_TRACE(TraceChannel::IR, "LLVM IR:");
                PEP_TRACE(TraceChannel::IR, module->toString());
            }

            if (auto err = module->verify()) {
                throw CompileError("Module Verification failed: {0}", llvm::toString(std::move(err)));
            }

            if (Opts->EmitLLVM) {
                emitIR(module->getModule());
            }

            if (!Opts->OutputPath.empty()) {
                emitObjFile(module->getModule());
            }

            llvm::outs().flush();
            llvm::errs().flush();

            return module;
        }

        static std::string ModuleFilename(const llvm::Module& module) {
            const auto& moduleSource = module.getSourceFileName();
            if (!moduleSource.empty()) {
                return std::filesystem::path(moduleSource).filename().replace_extension().string();
            }
            return module.getModuleIdentifier();
        }

        void emitObjFile(llvm::Module& module) {
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
            auto rm = llvm::Optional<llvm::Reloc::Model>();
            auto targetMachine = target->createTargetMachine(targetTriple, cpu, cpuFeatures, opt, rm);

            std::filesystem::path outputFile(Opts->BuildDir);
            std::filesystem::path inputFile(ModuleFilename(module));
            outputFile /= inputFile.filename().replace_extension(".o");

            auto objFilePath = outputFile.string();

            std::error_code errCode;
            llvm::raw_fd_ostream dest(objFilePath, errCode, llvm::sys::fs::OF_None);

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

            ObjFiles.emplace_back(objFilePath);
        }

        void emitIR(const llvm::Module& module) {
            std::filesystem::path outputPath(Opts->BuildDir);
            std::filesystem::path sourceFile(ModuleFilename(module));
            outputPath /= sourceFile.filename().replace_extension(".ll");

            std::error_code EC;
            llvm::raw_fd_ostream out(outputPath.string(), EC);
            if (EC) {
                throw CompileError("Unable to write to {0}: {1}", outputPath.string(), EC.message());
            }

            module.print(out, nullptr, false, false);
            PEP_VERBOSE("LLVM IR written to {0}", outputPath.string());
        }

        void link() override {
            Vector<const char*> args;

            Linker::link(Opts, ObjFiles);

            //            if (triple.isOSBinFormatELF()) {
            //                lld::elf::link(args, llvm::outs(), llvm::errs(), false, false);
            //            } else if (triple.isOSBinFormatMachO()) {
            //                lld::macho::link(args, llvm::outs(), llvm::errs(), false, false);
            //            } else if (triple.isOSBinFormatCOFF()) {
            //                lld::coff::link(args, llvm::outs(), llvm::errs(), false, false);
            //            }
        }

        void ensureBuildDirExists() const {
            auto buildDir = absolute(std::filesystem::path(Opts->BuildDir));
            if (!exists(buildDir)) {
                if (!create_directories(buildDir)) {
                    throw CompileError("Unable to create build dir {0}", buildDir.string());
                }
            }
        }

        static std::string findRuntimePath() {
            Vector<std::string> searchPaths = {
                "runtime",
                ".pep/runtime",
                ".pep/build/runtime",
            };

            for (int idx = 1; idx < 6; ++idx) {
                searchPaths.emplace_back(repeat("../", idx) + "runtime");
            }

            for (const auto& searchPath : searchPaths) {
                std::filesystem::path path(searchPath);
                if (std::filesystem::exists(path)) {
                    return absolute(path).string();
                }
            }
            throw InternalCompilerError("Could not find runtime");
        }

        static Vector<std::string> findRuntimeModuleSources(const std::string& runtimeDir) {
            Vector<std::string> sources;
            std::filesystem::path path(runtimeDir);
            for (const auto& file : std::filesystem::directory_iterator(path)) {
                if (file.path().extension() == ".pep") {
                    sources.emplace_back(absolute(file.path()).string());
                }
            }
            return sources;
        }

        static Vector<std::string> findRuntimeLibraries(const std::string& runtimeDir) {
            auto triple = llvm::Triple{llvm::sys::getDefaultTargetTriple()};
            Vector<std::string> libs;
            std::filesystem::path path(runtimeDir);
            for (const auto& file : std::filesystem::directory_iterator(path)) {
                if (triple.isOSWindows()) {
                    if (file.path().extension() == ".lib") {
                        libs.emplace_back(absolute(file.path()).string());
                    }
                } else {
                    if (file.path().extension() == ".a") {
                        libs.emplace_back(absolute(file.path()).string());
                    }
                }
            }
            return libs;
        }

        void importRuntime() {
            if (Opts->CompileRuntime) {
                auto runtimePath = findRuntimePath();
                auto runtimeSources = findRuntimeModuleSources(runtimePath);
                auto runtimeLibs = findRuntimeLibraries(runtimePath);
                Opts->Libraries.append(runtimeLibs);
                Opts->ImportPaths.insert(Opts->ImportPaths.begin(), runtimePath);
                Opts->SourceFiles.insert(Opts->SourceFiles.begin(), runtimeSources.begin(), runtimeSources.end());
            }
        }
    };

    Ref<Compiler> Compiler::Create(Ref<Options> options) {
        auto compiler = Ref<PepperCompiler>::New(options);
        compiler->importRuntime();
        return compiler;
    }

} // namespace pepper
