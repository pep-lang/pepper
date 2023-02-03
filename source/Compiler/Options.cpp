
#include "Compiler/Options.h"
#include <filesystem>

#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/MathExtras.h"

#define BIT_IDX(b) (llvm::countTrailingZeros((unsigned)b))

namespace pepper {
    using namespace llvm;
    using std::string;

    namespace cli {
        static cl::list<string> SourceFiles(cl::Sink, cl::Required, cl::desc("<input files>"));
        static cl::list<string> ImportPaths("I", cl::Prefix, cl::desc("Import search path(s)"));
        static cl::list<string> ForcedImports("import", cl::desc("Forced import for all modules"));
        static cl::list<string> Libraries("l", cl::desc("Libraries to link"));
        static cl::opt<string> OutputPath("o", cl::desc("Output binary"), cl::value_desc("filename"));
        static cl::opt<string> BuildPath(
            "build", cl::desc("Build directory, defaults to ./build"), cl::value_desc("path"));
        static cl::opt<bool> EmitLLVM("emit-llvm", cl::desc("Emit LLVM IR"));
        static cl::opt<bool> EmitDebugInfo("g", "emit-debug", cl::desc("Emit debugging information into binary"));
        static cl::opt<bool> Verbose("v", cl::desc("Verbose output"));
        static cl::opt<bool> NoRuntime("no-runtime", cl::desc("Skip runtime compilation"));
        static cl::bits<TraceChannel> TraceChannels(
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
    } // namespace cli

    static std::string PathToFilename(const std::string& path) {
        return std::filesystem::path(path).filename().string();
    }

    static std::string Normalize(const std::string& path) {
        return absolute(std::filesystem::path(path)).string();
    }

    Ref<Options> Options::FromCommandLine(int argc, const char** argv) {
        llvm::cl::ParseCommandLineOptions(argc, argv);
        auto opts = Defaults();
        opts->ProgramPath = argv[0];
        opts->SourceFiles.append(cli::SourceFiles.begin(), cli::SourceFiles.end());
        opts->SourceFiles =
            Query(opts->SourceFiles).map([&](auto& src) { return absolute(std::filesystem::path(src)).string(); });
        opts->PrimarySourceFile = opts->SourceFiles.front();

        if (cli::BuildPath != "") {
            opts->BuildDir = Normalize(cli::BuildPath);
        }

        if (cli::OutputPath != "") {
            opts->OutputPath = Normalize(cli::OutputPath);
            opts->ExeName = PathToFilename(cli::OutputPath);
        }

        opts->ImportPaths.append(cli::ImportPaths.begin(), cli::ImportPaths.end());
        opts->ForcedImports.append(cli::ForcedImports.begin(), cli::ForcedImports.end());
        opts->Libraries.append(cli::Libraries.begin(), cli::Libraries.end());

        opts->EmitLLVM = cli::EmitLLVM;
        opts->Verbose = cli::Verbose;
        opts->CompileRuntime = !cli::NoRuntime;
        opts->EmitDebugInfo = cli::EmitDebugInfo;
        opts->TraceChannels = cli::TraceChannels.getBits();
        if (cli::TraceAll)
            opts->TraceChannels = (unsigned int)TraceChannel::ALL;
        return opts;
    }

    Ref<Options> Options::Defaults() {
        auto opts = Ref<Options>::New();
        opts->BuildDir = (std::filesystem::current_path() / ".pep" / "build").string();
        opts->ForcedImports = {
            "internals",
            "range",
        };
        return opts;
    }

} // namespace pepper