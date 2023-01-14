
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
        static cl::opt<string> OutputPath("o", cl::desc("Output binary"), cl::value_desc("filename"));
        static cl::opt<string> BuildPath(
            "build", cl::desc("Build directory, defaults to ./build"), cl::value_desc("path"));
        static cl::opt<bool> EmitLLVM("emit-llvm", cl::desc("Emit LLVM IR"));
        static cl::opt<bool> Verbose("v", cl::desc("Verbose output"));
        static cl::bits<TraceChannel> TraceChannels(
            cl::desc("Trace channels to enable"),
            cl::values(clEnumValN(BIT_IDX(TraceChannel::Codegen), "Tcodegen", "CodeGen"),
                       clEnumValN(BIT_IDX(TraceChannel::AST), "Tast", "AST"),
                       clEnumValN(BIT_IDX(TraceChannel::Parser), "Tparser", "Parser"),
                       clEnumValN(BIT_IDX(TraceChannel::IR), "Tir", "IR"),
                       clEnumValN(BIT_IDX(TraceChannel::DebugInfo), "Tdebuginfo", "DebugInfo"),
                       clEnumValN(BIT_IDX(TraceChannel::ALL), "Tall", "All channels")));
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
        opts->SourceFiles.assign(cli::SourceFiles.begin(), cli::SourceFiles.end());
        opts->SourceFiles =
            Query(opts->SourceFiles).map([&](auto& src) { return absolute(std::filesystem::path(src)).string(); });

        if (cli::BuildPath != "") {
            opts->BuildDir = Normalize(cli::BuildPath);
        }

        if (cli::OutputPath != "") {
            opts->OutputPath = Normalize(cli::OutputPath);
            opts->ExeName = PathToFilename(cli::OutputPath);
        }

        opts->EmitLLVM = cli::EmitLLVM;
        opts->Verbose = cli::Verbose;
        opts->TraceChannels = cli::TraceChannels.getBits();
        return opts;
    }

    Ref<Options> Options::Defaults() {
        auto opts = Ref<Options>::New();
        opts->BuildDir = (std::filesystem::current_path() / ".pep" / "build").string();
        return opts;
    }

} // namespace pepper