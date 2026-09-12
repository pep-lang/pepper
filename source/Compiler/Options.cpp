
#include "Compiler/Options.h"
#include <filesystem>

#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/ADT/bit.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"

#define BIT_IDX(b) (llvm::countr_zero((unsigned)b))

namespace pepper {
    using namespace llvm;
    using std::string;

    namespace cli {
        static cl::list<string> source_files(cl::Sink, cl::Required, cl::desc("<input files>"));
        static cl::list<string> import_paths("I", cl::Prefix, cl::desc("Import search path(s)"));
        static cl::list<string> forced_imports("import", cl::desc("Forced import for all modules"));
        static cl::list<string> libraries("l", cl::desc("libraries to link"));
        static cl::opt<string> output_path("o", cl::desc("Output binary"), cl::value_desc("filename"));
        static cl::opt<string> BuildPath(
            "build", cl::desc("Build directory, defaults to ./build"), cl::value_desc("path"));
        static cl::opt<bool> emit_llvm("emit-llvm", cl::desc("Emit LLVM IR"));
        static cl::opt<bool> emit_debug_info("g", "emit-debug", cl::desc("Emit debugging information into binary"));
        static cl::opt<bool> Verbose("v", cl::desc("Verbose output"));
        static cl::opt<bool> NoRuntime("no-runtime", cl::desc("Skip runtime compilation"));
        static cl::bits<TraceChannel> trace_channels(
            "T",
            cl::Prefix,
            cl::desc("Trace channels to enable"),
            cl::values(clEnumValN(BIT_IDX(TraceChannel::Codegen), "codegen", "CodeGen"),
                       clEnumValN(BIT_IDX(TraceChannel::AST), "ast", "AST"),
                       clEnumValN(BIT_IDX(TraceChannel::Parser), "parser", "Parser"),
                       clEnumValN(BIT_IDX(TraceChannel::IR), "ir", "IR"),
                       clEnumValN(BIT_IDX(TraceChannel::DebugInfo), "debuginfo", "DebugInfo"),
                       clEnumValN(BIT_IDX(TraceChannel::Link), "link", "Link")));
        static cl::opt<bool> TraceAll("Tall");
        static cl::opt<bool> MSVC("MSVC");
    } // namespace cli

    static std::string PathToFilename(const std::string& path) {
        return std::filesystem::path(path).filename().string();
    }

    static std::string Normalize(const std::string& path) {
        return absolute(std::filesystem::path(path)).string();
    }

    static Triple GetHostTriple() {
        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        return Triple{targetTriple};
    }

    static std::string_view ExecutableExt() {
        auto triple = GetHostTriple();
        if (triple.isWindowsMSVCEnvironment()) {
            return ".exe";
        }
        return "";
    }

    Ref<Options> Options::from_command_line(int argc, const char** argv) {
        llvm::cl::ParseCommandLineOptions(argc, argv);
        auto opts = defaults();
        opts->program_path = argv[0];
        opts->source_files.append(cli::source_files.begin(), cli::source_files.end());
        opts->source_files =
            Query(opts->source_files).map([&](auto& src) { return absolute(std::filesystem::path(src)).string(); });
        opts->primary_source_file = opts->source_files.front();

        if (cli::BuildPath != "") {
            opts->build_dir = Normalize(cli::BuildPath);
        }

        if (cli::output_path != "") {
            opts->output_path = Normalize(cli::output_path);
            opts->exe_name = PathToFilename(cli::output_path);
        } else {
            auto primarySourceName =
                std::filesystem::path(opts->primary_source_file).filename().replace_extension(ExecutableExt());
            opts->output_path = (std::filesystem::current_path() / primarySourceName).string();
        }

        opts->import_paths.append(cli::import_paths.begin(), cli::import_paths.end());
        opts->forced_imports.append(cli::forced_imports.begin(), cli::forced_imports.end());
        opts->libraries.append(cli::libraries.begin(), cli::libraries.end());

        opts->emit_llvm = cli::emit_llvm;
        opts->verbose = cli::Verbose;
        opts->compile_runtime = !cli::NoRuntime;
        opts->emit_debug_info = cli::emit_debug_info;
        opts->trace_channels = cli::trace_channels.getBits();
        if (cli::TraceAll)
            opts->trace_channels = (unsigned int)TraceChannel::ALL;
        opts->msvc = cli::MSVC;
        return opts;
    }

    Ref<Options> Options::defaults() {
        auto opts = Ref<Options>::create();
        opts->build_dir = (std::filesystem::current_path() / ".pep" / "build").string();
        opts->forced_imports = {
            "internals",
            "range",
        };
        return opts;
    }

} // namespace pepper
