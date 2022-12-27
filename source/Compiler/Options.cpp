
#include "Compiler/Options.h"
#include <filesystem>

#include "llvm/Support/CommandLine.h"

namespace pepper {
    using namespace llvm;
    using std::string;

    namespace cli {
        static cl::list<string> SourceFiles(cl::ConsumeAfter, cl::Required, cl::desc("<input files>"));
        static cl::opt<string> OutputPath("o", cl::desc("Output binary"), cl::value_desc("filename"));
    } // namespace cli

    static std::string PathToFilename(const std::string& path) {
        return std::filesystem::path(path).filename().string();
    }

    Ref<Options> Options::fromCommandLine(int argc, const char** argv) {
        llvm::cl::ParseCommandLineOptions(argc, argv);
        auto opts = std::make_shared<Options>();
        opts->SourceFiles.assign(cli::SourceFiles.begin(), cli::SourceFiles.end());
        opts->OutputPath = cli::OutputPath;
        if (cli::OutputPath.length() > 0)
            opts->ModuleName = PathToFilename(cli::OutputPath);
        else
            opts->ModuleName = PathToFilename(cli::SourceFiles.front());

        return opts;
    }

} // namespace pepper