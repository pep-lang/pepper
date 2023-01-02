
#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "AST/AST.h"
#include "AST/Parser.h"
#include "Codegen/Context.h"
#include "Codegen/IR/Codegen.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Runtime.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/ADT/Optional.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"

namespace pepper {
    class PepperCompiler : public Compiler {
        Ref<Options> Opts;
        std::string ModuleName;
        std::string SourcePath;
        Ref<ModuleContext> Module;
        std::unique_ptr<Parser> ParserRef;
        std::unique_ptr<Codegen> IR;

      public:
        explicit PepperCompiler(Ref<Options> options)
            : Opts(options)
            , ModuleName(options->ModuleName) {
            llvm::InitializeNativeTarget();
            llvm::InitializeNativeTargetAsmPrinter();
            llvm::InitializeNativeTargetAsmParser();
        }

        Ref<ast::AST> parse(std::istream& inputStream, const std::string& sourceFile) {
            SourcePath = sourceFile;
            return ParserRef->parse(inputStream, sourceFile);
        }

        Vector<Ref<ModuleContext>> compile() override {
            Vector<Ref<ModuleContext>> modules;
            if (Opts->InputStream) {
                auto module = compile(*Opts->InputStream);
                modules.emplace_back(module);
            } else {
                for (const auto& sourceFile : Opts->SourceFiles) {
                    std::ifstream sourceStream(sourceFile, std::ios_base::in);
                    SourcePath = std::filesystem::path(sourceFile);
                    auto module = compile(sourceStream);
                    modules.emplace_back(module);
                }
            }
            return modules;
        }

        Ref<ModuleContext> compile(std::istream& sourceStream) {
            Module = Ref<ModuleContext>::New(ModuleName, SourcePath);
            auto Ctx = Ref<Context>::New(Module);
            ParserRef = std::make_unique<Parser>();
            IR = std::make_unique<Codegen>(Module);

            auto ast = parse(sourceStream, SourcePath);
            if (!ast || !Messages::errors().empty()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::AST)) {
                PEP_TRACE(TraceChannel::AST, "Parse tree:");
                ast->dump();
            }

            IR->generate(ast);

            if (!Messages::errors().empty()) {
                Query(Messages::errors()).each([](auto e) { std::cerr << e.message() << std::endl; });
                throw CompileError("Error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::IR)) {
                PEP_TRACE(TraceChannel::IR, "LLVM IR:");
                PEP_TRACE(TraceChannel::IR, Module->toString());
            }

            if (auto err = Module->verify()) {
                throw CompileError("Module Verification failed: {0}", llvm::toString(std::move(err)));
            }

            if (!Opts->OutputPath.empty()) {
                emitObjFile();
            }

            return Module;
        }

        //        std::string fileBasename(const std::string filePath) {
        //            std::filesystem::path path(filePath);
        //            return path.filename().string();
        //        }
        //
        //        std::string fileDirname(const std::string filePath) {
        //            std::fil
        //        }

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

            std::filesystem::path outputFile(Opts->OutputPath);
            std::filesystem::path inputFile(SourcePath);
            outputFile.replace_filename(inputFile.filename().replace_extension(".o"));

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
        }

        static std::string findRuntimePath() {
            Vector<std::string> searchPaths = {
                "runtime",
                "../../../../runtime",
            };

            for (const auto& searchPath : searchPaths) {
                std::filesystem::path path(searchPath);
                if (std::filesystem::exists(path)) {
                    return path.string();
                }
            }
            throw InternalCompilerError("Could not find runtime");
        }

        static Vector<std::string> findRuntimeModules(const std::string& runtimeDir) {
            Vector<std::string> modules;
            std::filesystem::path path(runtimeDir);
            for (const auto& file : std::filesystem::directory_iterator(path)) {
                if (file.path().extension() == ".pep") {
                    modules.emplace_back(file.path().string());
                }
            }
            return modules;
        }

        void compileRuntime() {
            auto savedOptions = Opts;
            auto savedTraceChannels = Messages::GetTraceChannels();

            Opts = Options::Defaults();
            Messages::SetTraceChannels(TraceChannel::NONE);
            auto runtimePath = findRuntimePath();
            auto moduleSources = findRuntimeModules(runtimePath);
            Opts->SourceFiles = moduleSources;
            auto modules = compile();

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
