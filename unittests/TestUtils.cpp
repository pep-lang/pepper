//
// Created by Justin Boswell on 1/2/23.
//

#include "TestUtils.h"
#include <filesystem>

#include "Compiler/Compiler.h"
#include "Compiler/Options.h"
#include "Core/Messages.h"
#include "JIT/Executor.h"
#include "Support/TestSupport.h"
#include "gtest/gtest.h"
#include "llvm/Support/FormatVariadic.h"

namespace TestUtils {
    using namespace pepper;

    std::string TestName(::testing::TestInfo* ti) {
        return llvm::formatv("{0}.{1}", ti->test_suite_name(), ti->name());
    }

    void AssertTrap(bool condition, const char* msg) {
        printf("ASSERT: %s: %d\n", msg, (int)condition);
        fflush(stdout);
        ASSERT_TRUE(condition) << msg;
    }

    std::string SupportModulePath() {
        return absolute(std::filesystem::current_path() / "TestSupport.pep").string();
    }

    int CompileAndRun(
        const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime) {
        SupportInit(AssertTrap);
        Messages::SetTraceChannels(TraceChannel::ALL);
        auto sourceStream = std::make_unique<std::istringstream>(source);
        auto options = Options::Defaults();
        options->ExeName = name;
        options->InputStream = std::move(sourceStream);
        options->CompileRuntime = compileRuntime;
        options->SourceFiles.emplace_back(SupportModulePath());
        auto compiler = Compiler::Create(options);
        auto module = compiler->compile();
        auto executor = Executor::Create();
        return executor->execute(module, entry);
    }
} // namespace TestUtils