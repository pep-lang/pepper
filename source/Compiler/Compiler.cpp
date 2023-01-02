
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
#include "Codegen/Symbols.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/TargetSelect.h"

namespace pepper {
    class PepperCompiler : public Compiler {
        std::string ModuleName;
        std::string SourcePath;
        Ref<ModuleContext> Module;
        std::unique_ptr<Parser> ParserRef;
        std::unique_ptr<Codegen> IR;

      public:
        explicit PepperCompiler(const std::string& moduleName, const std::string& sourceFile)
            : ModuleName(moduleName)
            , SourcePath(sourceFile) {
            llvm::InitializeNativeTarget();
            llvm::InitializeNativeTargetAsmPrinter();
            llvm::InitializeNativeTargetAsmParser();

            Module = Ref<ModuleContext>::New(moduleName, sourceFile);
            ParserRef = std::make_unique<Parser>();
            IR = std::make_unique<Codegen>(Module);
        }

        Ref<ast::AST> parse(std::istream& inputStream, const std::string& sourceFile) {
            SourcePath = sourceFile;
            return ParserRef->parse(inputStream, sourceFile);
        }

        Ref<ModuleContext> compile(const std::string& sourceFile) override {
            std::ifstream sourceStream(sourceFile, std::ios_base::in);
            SourcePath = std::filesystem::path(sourceFile);
            return compile(sourceStream);
        }

        Ref<ModuleContext> compile(std::istream& sourceStream) override {
            auto ast = parse(sourceStream, SourcePath);
            if (!ast || Messages::errors().size()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::AST)) {
                PEP_TRACE(TraceChannel::AST, "Parse tree:");
                ast->dump();
            }

            IR->generate(ast);

            if (Messages::errors().size()) {
                Query(Messages::errors()).each([](auto e) { std::cerr << e.message() << std::endl; });
                throw CompileError("Error(s) encountered, cannot continue");
            }

            if (PEP_TRACING(TraceChannel::IR)) {
                PEP_TRACE(TraceChannel::IR, "LLVM IR:");
                PEP_TRACE(TraceChannel::IR, Module->toString());
            }

            if (auto err = Module->verify()) {
                Messages::Report<Error>("Module Verification failed: {0}", llvm::toString(std::move(err)));
                throw CompileError("Verification failed, cannot continue");
            }

            return Module;
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
            auto traceChannels = Messages::GetTraceChannels();
            Messages::SetTraceChannels(TraceChannel::NONE);
            auto runtimePath = findRuntimePath();
            auto moduleSources = findRuntimeModules(runtimePath);
            for (const auto& source : moduleSources) {
                auto name = std::filesystem::path(source).filename().string();
                compile(source);
            }
            Messages::SetTraceChannels(traceChannels);
        }
    };

    Ref<Compiler> Compiler::Create(const std::string& moduleName, const std::string& sourceFilePath) {
        auto compiler = Ref<PepperCompiler>::New(moduleName, sourceFilePath);
        compiler->compileRuntime();
        return compiler;
    }

} // namespace pepper
