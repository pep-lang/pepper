
#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>
#include <iostream>

#include "AST/AST.h"
#include "CodeGen/CodeGenModule.h"
#include "CodeGen/CodeGenerator.h"
#include "Compiler/Linker.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Frontend/Context.h"
#include "Frontend/Runtime.h"
#include "Parser/Parser.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/Optional.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IRReader/IRReader.h"
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
        std::string SourcePath;
        Ref<CodeGenModule> Module;

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

            Module = Ref<CodeGenModule>::New(ModuleName, SourcePath);
        }

        Vector<Ref<CodeGenModule>> compile() override {
            auto Ctx = Ref<Context>::New(Module);
            Vector<Ref<CodeGenModule>> modules;
            if (Opts->InputStream) {
                SourcePath = ModuleName;
                auto module = compile(*Opts->InputStream);
                modules.emplace_back(module);
            } else {
                for (const auto& sourceFile : Opts->SourceFiles) {
                    std::ifstream sourceStream(sourceFile, std::ios_base::in);
                    SourcePath = std::filesystem::path(sourceFile).string();
                    auto module = compile(sourceStream);
                    modules.emplace_back(module);
                }
            }
            return modules;
        }

        Ref<CodeGenModule> compile(std::istream& sourceStream) {
            ensureBuildDirExists();

            Parser parser;
            auto ast = parser.parse(sourceStream, SourcePath);
            if (!ast || !Messages::errors().empty()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            ast::TransformPass transform(ast);
            ast = transform.run();

            if (PEP_TRACING(TraceChannel::AST)) {
                PEP_TRACE(TraceChannel::AST, "Parse tree:");
                ast->dump();
            }

            CodeGenerator codeGen(Module);
            codeGen.generate(ast);

            if (!Messages::errors().empty()) {
                Query(Messages::errors()).each([](auto e) { llvm::errs() << e.message() << "\n"; });
                throw CompileError("Error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::IR)) {
                PEP_TRACE(TraceChannel::IR, "LLVM IR:");
                PEP_TRACE(TraceChannel::IR, Module->toString());
            }

            if (auto err = Module->verify()) {
                throw CompileError("Module Verification failed: {0}", llvm::toString(std::move(err)));
            }

            if (Opts->EmitLLVM) {
                emitIR();
            }

            if (!Opts->OutputPath.empty()) {
                emitObjFile();
            }

            llvm::outs().flush();
            llvm::errs().flush();

            return Module;
        }

        void emitObjFile() {
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
            std::filesystem::path inputFile(SourcePath);
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

            pass.run(*(*Module));
            dest.flush();

            PEP_VERBOSE("Object file written to {0}", outputFile.string());

            ObjFiles.emplace_back(objFilePath);
        }

        void emitIR() {
            std::filesystem::path outputPath(Opts->BuildDir);
            std::filesystem::path sourceFile(SourcePath);
            outputPath /= sourceFile.filename().replace_extension(".ll");

            std::error_code EC;
            llvm::raw_fd_ostream out(outputPath.string(), EC);
            if (EC) {
                throw CompileError("Unable to write to {0}: {1}", outputPath.string(), EC.message());
            }

            const auto& module = Module->getModule();
            module.print(out, nullptr, false, false);
            PEP_VERBOSE("LLVM IR written to {0}", outputPath.string());
        }

        static Ref<CodeGenModule> loadIR(const std::string& irFilePath) {
            llvm::SMDiagnostic err;
            auto context = std::make_unique<llvm::LLVMContext>();
            auto module = llvm::parseIRFile(irFilePath, err, *context);
            if (!module) {
                throw CompileError("Failed to load IR from {0}: {1}", irFilePath, err.getMessage());
            }

            return Ref<CodeGenModule>::New(std::move(context), std::move(module));
        }

        Vector<Ref<CodeGenModule>> loadIR() {
            Vector<Ref<CodeGenModule>> modules;
            for (const auto& sourceFilePath : Opts->SourceFiles) {
                auto irFilePath = std::filesystem::path(sourceFilePath).replace_extension(".ll").string();
                auto module = loadIR(irFilePath);
                modules.emplace_back(module);
            }
            return modules;
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
                "../../../../runtime",
                "../../../runtime",
            };

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

        static Vector<std::string> findRuntimeModuleObjects(const std::string& runtimeDir) {
            Vector<std::string> objs;
            std::filesystem::path path(runtimeDir);
            for (const auto& file : std::filesystem::directory_iterator(path)) {
                if (file.path().extension() == ".o" || file.path().extension() == ".obj") {
                    objs.emplace_back(absolute(file.path()).string());
                }
            }
            return objs;
        }

        static Vector<std::string> findNewerRuntimeSources(const Vector<std::string>& moduleSources,
                                                           const Vector<std::string>& moduleObjects) {
            Vector<std::string> outdatedSources;
            for (const auto& source : moduleSources) {
                std::filesystem::path sourcePath(source);
                auto maybeObject = Query(moduleObjects).find([&](auto& obj) {
                    return std::filesystem::path(obj).filename().replace_extension() ==
                           sourcePath.filename().replace_extension();
                });
                if (!maybeObject) {
                    outdatedSources.emplace_back(source);
                    break;
                }
                auto objectPath = std::filesystem::path(maybeObject.value());
                auto sourceWriteTime = std::filesystem::last_write_time(sourcePath);
                auto objectWriteTime = std::filesystem::last_write_time(objectPath);
                if (sourceWriteTime > objectWriteTime) {
                    outdatedSources.emplace_back(source);
                    break;
                }
            }
            return outdatedSources;
        }

        void compileRuntime() {
            auto savedOptions = Opts;
            auto savedTraceChannels = Messages::GetTraceChannels();

            Opts = Options::Defaults();
            // Messages::SetTraceChannels(TraceChannel::NONE);
            ensureBuildDirExists();
            auto runtimePath = findRuntimePath();
            auto runtimeSources = findRuntimeModuleSources(runtimePath);
            auto runtimeObjects = findRuntimeModuleObjects(Opts->BuildDir);
            auto newerSources = findNewerRuntimeSources(runtimeSources, runtimeObjects);

            if (!newerSources.empty()) {
                Opts->SourceFiles = newerSources;
                Opts->EmitLLVM = true;
                Opts->OutputPath = runtimePath;
                llvm::outs() << "Runtime modules outdated, compiling"
                             << "\n";
                compile();
            }

            // load all IR
            auto irFiles = Query(runtimeSources).map([&](auto& src) {
                return (std::filesystem::path(Opts->BuildDir) / std::filesystem::path(src).filename()).string();
            });
            Opts->SourceFiles = irFiles;
            loadIR();

            Opts = savedOptions;
            Messages::SetTraceChannels(savedTraceChannels);
        }
    };

    Ref<Compiler> Compiler::Create(Ref<Options> options) {
        auto compiler = Ref<PepperCompiler>::New(options);
        compiler->compileRuntime();
        return compiler;
    }

} // namespace pepper
