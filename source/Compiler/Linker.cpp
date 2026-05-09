
#include "Compiler/Linker.h"
#include <filesystem>
#include <optional>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Program.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

#define PEP_TRACE_LINK(fmt, ...) PEP_TRACE(TraceChannel::Link, fmt, __VA_ARGS__)

namespace pepper {
    using namespace llvm;

    static void RunAndGetCommandOutput(
        const char* exePath, ArrayRef<llvm::StringRef> argv, SmallString<sys::fs::DefaultReadChunkSize>& buffer) {
        using namespace llvm::sys;

        SmallString<sys::fs::DefaultReadChunkSize> tmpFile;
        fs::createUniquePath(std::filesystem::temp_directory_path().string() + ".%%%%%%%.tmp", tmpFile, true);

        const std::optional<StringRef> Redirects[] = {
            /*STDIN=*/std::nullopt, /*STDOUT=*/StringRef{tmpFile}, /*STDERR=*/std::nullopt};
        std::string errors;
        int rc = ExecuteAndWait(exePath, argv, /*env=*/std::nullopt, Redirects, 0, 0, &errors);
        if (rc != 0) {
            throw InternalCompilerError("Failed to capture output from {0}: {1}", exePath, errors);
        }

        uint64_t size = 0;
        auto err = fs::file_size(tmpFile, size);
        if (err)
            throw InternalCompilerError("Failed to get size of {0}: {1}", tmpFile, err.message());
        buffer.resize(size);

        int fd = 0;
        err = fs::openFileForRead(tmpFile, fd);
        if (err)
            throw InternalCompilerError("Failed to read captured output from {0}: {1}", exePath, err.message());
        auto file = fs::convertFDToNativeFile(fd);
        auto read = fs::readNativeFile(file, buffer);
        if (!read)
            throw InternalCompilerError(
                "Failed to read captured output from {0}: {1}", exePath, llvm::toString(read.takeError()));
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

    static std::string GetMSVCToolsPath() {
        SmallString<sys::fs::DefaultReadChunkSize> output;
        auto vswhere = sys::findProgramByName("vswhere");
        if (vswhere) {
            Vector<StringRef> args = {
                "-latest", "-find", "**\\link.exe"
            };
            RunAndGetCommandOutput(vswhere.get().c_str(), args, output);
            for (auto& line : llvm::split(output, "\n")) {
                if (llvm::is_contained(line, "Hostx64\\x64")) {
                    line = line.rtrim();
                    line.consume_back("\\link.exe");
                    return line.str();
                }
            }
        }
        return {};
    }

    static Vector<StringRef> GetMSVCEnv(StringRef runtimeDir) {
        static Vector<std::string> Env;
        if (Env.empty()) {
            auto vswhere = sys::findProgramByName("vswhere");
            if (!vswhere) {
                return {};
            }

            auto cmdExe = sys::findProgramByName("cmd");
            auto msvcBat = (std::filesystem::path(runtimeDir.str()) / "msvc.bat").string();
            Vector<StringRef> args = {"/c", msvcBat, "amd64"};
            SmallString<sys::fs::DefaultReadChunkSize> output;
            RunAndGetCommandOutput(cmdExe.get().c_str(), args, output);
            for (auto& line : llvm::split(output, "\n")) {
                line = line.rtrim();
                if (llvm::is_contained(line, "=")) {
                    Env.emplace_back(line);
                }
            }
        }
        Vector<StringRef> env(Env.begin(), Env.end());
        return env;
    }

    static std::string GetRuntimePath(Ref<Options> opts) {
        for (const auto& lib : opts->Libraries) {
            if (lib.ends_with("Support.lib")) {
                StringRef libPath(lib);
                libPath.consume_back("\\Support.lib");
                return libPath.str();
            }
        }
        return {};
    }

    static std::string ResolveWindowsLink(Ref<Options> opts) {
        const std::string programPath = opts->ProgramPath;

        Vector<std::string> linkExeNames = {
            "lld-link",
        };

        Vector<std::string> searchPaths = {
            std::filesystem::path(programPath).parent_path().string(),
        };

        if (opts->MSVC) {
            linkExeNames.insert(linkExeNames.begin(), "link");
            const std::string toolsPath = GetMSVCToolsPath();
            searchPaths.emplace_back(toolsPath);
        }

        for (auto& linkExeName : linkExeNames) {
            auto linkExe = sys::findProgramByName(linkExeName, Vector<StringRef>{searchPaths.begin(), searchPaths.end()});
            if (linkExe) {
                PEP_VERBOSE("Found MSVC link.exe: {0}", linkExe.get());
                return linkExe.get();
            }
        }

        throw InternalCompilerError("Cannot find link program(s) {0}", llvm::join(linkExeNames, ", "));
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

        auto outputPath = std::filesystem::path(opts->OutputPath);
        auto outputDir = outputPath.parent_path();
        auto outputFilename = outputPath.filename();

        auto runtimePath = GetRuntimePath(opts);
        auto msvcEnv = GetMSVCEnv(runtimePath);
        auto linkExe = ResolveWindowsLink(opts);

        auto triple = GetHostTriple();

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
            "/nologo",
            "/pdb:" + pdbPath,
            "/debug:full",
            "/version:0.0",
            "/machine:x64",
            //"/entry:main",
            "/defaultlib:msvcrt",
            "/nodefaultlib:msvcrtd",
            "/subsystem:console",
            "vcruntime.lib",
            "msvcprt.lib",
            "ucrt.lib",
            //"libcmt.lib",
            "kernel32.lib",
            "user32.lib",
            "shell32.lib",
        };
        linkArgs.append(opts->Libraries);
        linkArgs.emplace_back("/out:" + opts->OutputPath);
        linkArgs.append(objFiles);

        PEP_VERBOSE("{0}.exe {1}", linkExe, llvm::join(linkArgs, " "));

        auto linkArgsView = Query(linkArgs).select<StringRef>().toVector();
        std::string lldErrors;
        // link.exe is weird and will only output to the working directory, so switch it just for the link invocation
        auto cwd = std::filesystem::current_path();
        std::filesystem::current_path(outputDir);
        auto rc = sys::ExecuteAndWait(linkExe, linkArgsView, msvcEnv, {}, 0, 0, &lldErrors);
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
            });
            // clang-format on
        }

        ldArgs.append(objFiles);

        for (auto& lib : opts->Libraries) {
            auto path = std::filesystem::path(lib);
            if (llvm::is_contained(lib, std::filesystem::path::preferred_separator)) {
                auto libDir = absolute(path).parent_path().string();
                ldArgs.emplace_back("-L" + libDir);
            }
        }

        ldArgs.emplace_back("-lSystem");
        for (auto& lib : opts->Libraries) {
            auto libName = std::filesystem::path(lib).filename().replace_extension().string();
            if (libName.starts_with("lib"))
                libName = libName.substr(3);
            ldArgs.emplace_back("-l" + libName);
        }

        PEP_VERBOSE("ld {0}", llvm::join(ldArgs, " "));

        auto ldArgsView = Query(ldArgs).select<StringRef>().toVector();
        std::string lldErrors;
        auto rc = sys::ExecuteAndWait(lldPath, ldArgsView, std::nullopt, std::nullopt, 0, 0, &lldErrors);
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
