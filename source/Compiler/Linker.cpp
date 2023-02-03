
#include "Compiler/Linker.h"
#include <filesystem>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/Program.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"

#define PEP_TRACE_LINK(fmt, ...) PEP_TRACE(TraceChannel::Link, fmt, __VA_ARGS__)

namespace pepper {
    using namespace llvm;

    static void RunAndGetCommandOutput(
        const char* exePath, ArrayRef<llvm::StringRef> argv, SmallString<sys::fs::DefaultReadChunkSize>& buffer) {
        using namespace llvm::sys;

        SmallString<sys::fs::DefaultReadChunkSize> tmpFile;
        fs::createUniquePath(std::string(exePath) + ".%%%%%%%.tmp", tmpFile, true);

        const Optional<StringRef> Redirects[] = {/*STDIN=*/None, /*STDOUT=*/StringRef{tmpFile}, /*STDERR=*/None};
        std::string errors;
        int rc = ExecuteAndWait(exePath, argv, /*env=*/llvm::None, Redirects, 0, 0, &errors);
        if (rc != 0) {
            throw InternalCompilerError("Failed to capture output from {0}: {1}", exePath, errors);
        }

        int fd = 0;
        auto opened = fs::openFileForRead(tmpFile, fd);
        if (!opened)
            throw InternalCompilerError("Failed to read captured output from {0}", exePath, opened.message());
        auto file = fs::convertFDToNativeFile(fd);
        auto read = fs::readNativeFile(file, buffer);
        if (!read)
            throw InternalCompilerError(
                "Failed to read captured output from {0}", exePath, llvm::toString(read.takeError()));
    }

    static Vector<std::string> GetLLVMConfig(StringRef searchPath) {
        auto llvmConfig = sys::findProgramByName("llvm-config", {searchPath});
        if (!llvmConfig) {
            throw InternalCompilerError("Cannot find llvm-config: {0}", llvmConfig.getError().message());
        }

        Vector<StringRef> llvmConfigArgs = {
            "--ldflags",
            "--system-libs",
        };

        SmallString<sys::fs::DefaultReadChunkSize> output;
        RunAndGetCommandOutput(llvmConfig.get().c_str(), llvmConfigArgs, output);
        Vector<std::string> lines;
        for (auto& line : llvm::split(output, "\n")) {
            lines.emplace_back(line);
        }
        return lines;
    }

    Triple GetHostTriple() {
        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        return Triple{targetTriple};
    }

    void WriteResponseFile(const std::string& responseFile, const Vector<std::string>& objFiles) {
        std::string responseContents;
        for (const auto& objFile : objFiles) {
            responseContents += objFile + "\n";
        }

        // visual studio tools only understand UTF-16
        sys::writeFileWithEncoding(responseFile, responseContents, llvm::sys::WEM_UTF16);
    }

    void WindowsLink(Ref<Options> opts, const Vector<std::string>& objFiles) {
        std::string programPath = opts->ProgramPath;
        auto outputPath = std::filesystem::path(opts->OutputPath);
        auto outputDir = outputPath.parent_path();
        auto outputFilename = outputPath.filename();

        std::string searchPath = std::filesystem::path(programPath).parent_path().string();

        auto triple = GetHostTriple();
        std::string lldExe = "lld-link";
        std::string libExe = "llvm-lib";
        if (triple.isWindowsMSVCEnvironment())
            lldExe = "lld-link";

        auto lib = sys::findProgramByName(libExe, {searchPath});
        if (!lib) {
            throw InternalCompilerError("Cannot find lib program {0}: {1}", libExe, lib.getError().message());
        }

        auto lld = sys::findProgramByName(lldExe, {searchPath});
        if (!lld) {
            throw InternalCompilerError("Cannot find link program {0}: {1}", lldExe, lld.getError().message());
        }

        //        std::string libPath = outputPath.replace_extension(".lib").string();
        //        auto libResponseFile = outputPath.replace_extension().replace_extension(".rsp").string();
        //        WriteResponseFile(libResponseFile, objFiles);
        //        Vector<std::string> libArgs = {
        //            //"@" + libResponseFile,
        //            "/machine:x64",
        //            "/out:" + libPath,
        //        };
        //        libArgs.append(objFiles);

        //        auto libArgsView = Query(libArgs).select<StringRef>().toVector();
        //        std::string libErrors;
        //        auto libRetCode = sys::ExecuteAndWait(lib.get(), libArgsView, llvm::None, llvm::None, 0, 0,
        //        &libErrors); if (libRetCode != 0)
        //            throw CompileError("Library assembly failed: {0}", libErrors);

        std::string pdbPath = outputPath.replace_extension(".pdb").string();
        Vector<std::string> linkArgs = {
            //"@" + libResponseFile,
            //"/implib:" + libPath,
            //"/verbose",
            //"/verbose:lib",
            "/pdb:" + pdbPath,
            "/version:0.0",
            "/machine:x64",
            "/debug",
            "/entry:main",
            "/defaultlib:msvcrt",
            "/subsystem:console",
            "ucrt.lib",
            "libcmt.lib",
            "kernel32.lib",
            "user32.lib",
            "shell32.lib",
            "vcruntime.lib",
        };
        linkArgs.append(opts->Libraries);
        linkArgs.emplace_back("/out:" + opts->OutputPath);
        linkArgs.append(objFiles);

        PEP_VERBOSE("lld-link.exe {0}", llvm::join(linkArgs, " "));

        auto linkArgsView = Query(linkArgs).select<StringRef>().toVector();
        std::string lldErrors;
        // link.exe is weird and will only output to the working directory, so switch it just for the link invocation
        auto cwd = std::filesystem::current_path();
        std::filesystem::current_path(outputDir);
        auto rc = sys::ExecuteAndWait(lld.get(), linkArgsView, llvm::None, llvm::None, 0, 0, &lldErrors);
        std::filesystem::current_path(cwd);
        if (rc != 0)
            throw CompileError("Link failed: {0}", lldErrors);
    }

    void PosixLink(Ref<Options> opts, const Vector<std::string>& objFiles) {
        std::string programPath = opts->ProgramPath;
        auto outputPath = std::filesystem::path(opts->OutputPath);
        auto outputDir = outputPath.parent_path();
        auto outputFilename = outputPath.filename();

        std::string searchPath = std::filesystem::path(programPath).parent_path().string();

        auto triple = GetHostTriple();

        auto lldExe = "ld"; // triple.isMacOSX() ? "ld64.lld" : "ld.lld";
        // auto lld = sys::findProgramByName(lldExe, {searchPath});
        auto lld = sys::findProgramByName(lldExe);
        if (!lld) {
            throw InternalCompilerError("Cannot find link program {0}: {1}", lldExe, lld.getError().message());
        }
        auto lldPath = lld.get();

        // clang-format off
        Vector<std::string> ldArgs = {
            "-demangle",
            "-dynamic",
            "-arch", "x86_64",
            "-o", outputPath.string(),
        };
        // clang-format on
        if (triple.isMacOSX()) {
            // clang-format off
            ldArgs.append({
                "-platform_version", "macos", "12.1.0", "12.3",
                "-syslibroot", "/Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk",
                "-lSystem",
            });
            // clang-format on
        }

        for (auto& lib : opts->Libraries) {
            ldArgs.emplace_back("-l" + lib);
        }

        ldArgs.append(objFiles);

        PEP_VERBOSE("ld {0}", llvm::join(ldArgs, " "));

        auto ldArgsView = Query(ldArgs).select<StringRef>().toVector();
        std::string lldErrors;
        auto rc = sys::ExecuteAndWait(lldPath, ldArgsView, llvm::None, llvm::None, 0, 0, &lldErrors);
        if (rc != 0)
            throw CompileError("Link failed: {0}", lldErrors);
    }

    void Linker::link(Ref<Options> opts, const Vector<std::string>& objFiles) {
        auto triple = GetHostTriple();
        if (triple.isWindowsMSVCEnvironment())
            WindowsLink(opts, objFiles);
        else
            PosixLink(opts, objFiles);
    }
} // namespace pepper
