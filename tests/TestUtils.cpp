//
// Created by Justin Boswell on 1/2/23.
//

#include "TestUtils.h"

#include "Compiler/Compiler.h"
#include "Compiler/Options.h"
#include "Core/Messages.h"
#include "Frontend/Runtime.h"
#include "JIT/Executor.h"
#include "Support.h"
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

    void RegisterImports() {
        Runtime::Import("void", "trace_int", {{"int", "value"}, {"u8*", "message"}});
        Runtime::Import("void", "trace_ptr", {{"void*", "ptr"}, {"u8*", "message"}});
        Runtime::Import("void", "test_assert", {{"bool", "condition"}, {"u8*", "message"}});
    }

    int CompileAndRun(const std::string& name, const std::string& source, const std::string& entry) {
        RegisterImports();
        SupportInit(AssertTrap);
        Messages::SetTraceChannels(TraceChannel::ALL);
        auto sourceStream = std::make_unique<std::istringstream>(source);
        auto options = Options::Defaults();
        options->ExeName = name;
        options->SourceFiles.emplace_back(name);
        options->InputStream = std::move(sourceStream);
        auto compiler = Compiler::Create(options);
        auto modules = compiler->compile();
        auto module = modules[0];
        auto executor = Executor::Create();
        return executor->execute(module, entry);
    }
} // namespace TestUtils