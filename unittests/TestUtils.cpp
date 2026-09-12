//
// Created by Justin Boswell on 1/2/23.
//

#include "TestUtils.h"
#include <filesystem>

#include "Compiler/Compiler.h"
#include "Compiler/Options.h"
#include "Core/Messages.h"
#include "Support/TestSupport.h"
#include "gtest/gtest.h"
#include "llvm/Support/FormatVariadic.h"

namespace TestUtils {
    using namespace pepper;

    std::string TestName(::testing::TestInfo* ti) {
        return llvm::formatv("{0}.{1}.pep", ti->test_suite_name(), ti->name());
    }

    void AssertTrap(bool condition, const char* msg) {
        printf("ASSERT: %s: %d\n", msg, (int)condition);
        fflush(stdout);
        ASSERT_TRUE(condition) << msg;
    }

    std::string SupportModulePath() {
        return absolute(std::filesystem::current_path() / "TestSupport.pep").string();
    }

    Vector<std::string> CompileModule(
        const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime) {
        SupportInit(AssertTrap);
        Messages::set_trace_channels(TraceChannel::ALL);
        auto sourceStream = std::make_unique<std::istringstream>(source);
        auto options = Options::defaults();
        options->exe_name = name;
        options->input_stream = std::move(sourceStream);
        options->compile_runtime = compileRuntime;
        options->source_files.emplace_back(SupportModulePath());
        options->trace_channels = uint64_t(TraceChannel::ALL);
        options->emit_llvm = true;
        auto compiler = Compiler::Create(options);
        compiler->compile();
        return compiler->get_object_file_paths();
    }

    int CompileAndRun(
        const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime) {
        return CompileAndRunResult<int>(name, source, entry, compileRuntime);
    }

    int Compile(const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime) {
        auto obj_files = CompileModule(name, source, entry, compileRuntime);
        return obj_files.empty() ? -1 : 0;
    }
} // namespace TestUtils
