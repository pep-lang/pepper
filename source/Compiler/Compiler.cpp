
#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>
#include <ios>
#include <istream>
#include <iterator>
#include <memory>
#include <sstream>
#include <string>

#include "CodeGen/CodeGenerator.h"
#include "Compiler/ImportResolver.h"
#include "Compiler/Linker.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Core/Ref.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "Parser/BoostParser.h"
#include "Parser/Lexer.h"
#include "Parser/LexyParser.h"
#include "Parser/Parser.h"
#include "Sema/Model/Module.h"
#include "Sema/ModelBuilder.h"
#include "Sema/SemaContext.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"

namespace pepper {
    class PepperCompiler : public Compiler {
        Ref<Options> options;

        // Re-used internals per module
        std::string module_name;
        std::unique_ptr<SemaContext> sema_ctx;

        // Collected obj files for linking
        Vector<std::string> obj_files;

      public:
        explicit PepperCompiler(Ref<Options> options)
            : options(options)
            , module_name(options->exe_name) {
            llvm::InitializeNativeTarget();
            llvm::InitializeNativeTargetAsmPrinter();
            llvm::InitializeNativeTargetAsmParser();

            if (options->verbose)
                Messages::enable_verbose_output();
            if (options->trace_channels)
                Messages::set_trace_channels(options->trace_channels);

            sema_ctx = std::make_unique<SemaContext>();
        }

        void compile() override {
            ensure_build_dir_exists();

            Ref<sema::Module> module = Ref<sema::Module>::create(sema::ModuleKind::Main);
            ImportResolver importer(options->import_paths);

            llvm::StringSet seen_files;
            auto sourceFiles = options->source_files;
            seen_files.insert(sourceFiles.begin(), sourceFiles.end());

            auto collectImports = [&](const std::string& sourceFile, Ref<sema::Module> ast) {
                const auto& importNodes = ast->imports();
                for (const auto& import : importNodes) {
                    auto importPath = importer.resolve(sourceFile, import->Module, import->Local);
                    if (importPath.empty())
                        throw CompileError(import->source_loc, "Cannot resolve import {0}", import->Module);
                    if (!seen_files.contains(importPath)) {
                        sourceFiles.emplace_back(importPath);
                        seen_files.insert(llvm::StringRef{importPath});
                    }
                }
            };

            if (options->input_stream) {
                PEP_TRACE(TraceChannel::Parser, "Parsing input_stream");
                auto ast = parse(*options->input_stream, module_name);
                if (!ast) {
                    return;
                }
                module->merge(ast);
                collectImports(module_name, ast);
            }

            // TODO: do the parse/sema in parallel
            while (!sourceFiles.empty()) {
                const auto& sourceFile = sourceFiles.pop_back_val();
                std::ifstream sourceStream(sourceFile, std::ios_base::in);
                PEP_TRACE(TraceChannel::Parser, "Parsing {0}...", sourceFile);
                auto ast = parse(sourceStream, sourceFile);
                module->merge(ast);

                // Resolve all imports and add them to the list to process if necessary
                collectImports(sourceFile, ast);
            }

            sema::TransformPass transform(module);
            module = transform.run();

            if (PEP_TRACING(TraceChannel::AST)) {
                PEP_TRACE(TraceChannel::AST, "Parse tree:");
                module->dump();
            }

            codegen(module);
        }

        static Vector<std::string> read_lines(const std::string source) {
            const char* eol = "\n";
            auto idx = source.find("\n");
            if (idx != std::string::npos) {
                if (idx > 0 && source[idx - 1] == '\r') {
                    eol = "\r\n";
                }
            }
            const auto lines = llvm::split(source, eol);
            return {lines.begin(), lines.end()};
        }

        static Ref<sema::Module> parse(std::istream& sourceStream, const std::string& sourcePath) {
            const std::string buffer(std::istreambuf_iterator(sourceStream), {});

            const auto lines = read_lines(buffer);
            Sources::add({sourcePath, lines});

            const auto lexy_parser = parser::LexyParser::create(sourcePath, buffer);
            if (!lexy_parser->parse()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            auto builder = sema::ModelBuilder(lexy_parser->tree(), sema::ModuleKind::SourceFile);
            auto module = builder.build();
            if (!module) {
                throw CompileError("Compilation error(s) encountered, cannot continue");
            }

            return module;
        }

        void codegen(Ref<sema::Module> model) {
            CodeGenerator generator(CodeGenerator::Type::LLVM, *sema_ctx, module_name, options->primary_source_file);
            generator.generate(model, options);

            if (!Messages::errors().empty()) {
                Query(Messages::errors()).each([](auto e) { llvm::errs() << e.message() << "\n"; });
                throw CompileError("Error(s) encountered, cannot continue");
            }

            llvm::outs().flush();
            llvm::errs().flush();

            obj_files.push_back(generator.get_object_file_path());
        }

        void link() override {
            Vector<const char*> args;

            Linker::link(options, obj_files);

            //            if (triple.isOSBinFormatELF()) {
            //                lld::elf::link(args, llvm::outs(), llvm::errs(), false, false);
            //            } else if (triple.isOSBinFormatMachO()) {
            //                lld::macho::link(args, llvm::outs(), llvm::errs(), false, false);
            //            } else if (triple.isOSBinFormatCOFF()) {
            //                lld::coff::link(args, llvm::outs(), llvm::errs(), false, false);
            //            }
        }

        Vector<std::string> get_object_file_paths() const override {
            return obj_files;
        }

        void ensure_build_dir_exists() const {
            auto buildDir = absolute(std::filesystem::path(options->build_dir));
            if (!exists(buildDir)) {
                if (!create_directories(buildDir)) {
                    throw CompileError("Unable to create build dir {0}", buildDir.string());
                }
            }
        }

        static std::string find_runtime_path() {
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

        static Vector<std::string> find_runtime_module_sources(const std::string& runtimeDir) {
            Vector<std::string> sources;
            std::filesystem::path path(runtimeDir);
            for (const auto& file : std::filesystem::directory_iterator(path)) {
                if (file.path().extension() == ".pep") {
                    sources.emplace_back(absolute(file.path()).string());
                }
            }
            return sources;
        }

        static Vector<std::string> find_runtime_libraries(const std::string& runtimeDir) {
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

        void import_runtime() {
            if (options->compile_runtime) {
                auto runtimePath = find_runtime_path();
                auto runtimeSources = find_runtime_module_sources(runtimePath);
                auto runtimeLibs = find_runtime_libraries(runtimePath);
                options->libraries.append(runtimeLibs);
                options->import_paths.insert(options->import_paths.begin(), runtimePath);
                options->source_files.insert(
                    options->source_files.begin(), runtimeSources.begin(), runtimeSources.end());
            }
        }
    };

    Ref<Compiler> Compiler::Create(Ref<Options> options) {
        auto compiler = Ref<PepperCompiler>::create(options);
        compiler->import_runtime();
        return compiler;
    }

} // namespace pepper
