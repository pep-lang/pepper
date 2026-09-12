

#include <filesystem>
#include <ranges>
#include <regex>

#include "TestUtils.h"
#include "gtest/gtest.h"
#include "llvm/Support/MemoryBuffer.h"

std::string file_to_string(const std::filesystem::path& path) {
    using namespace llvm;

    auto bufOrErr = MemoryBuffer::getFile(path.string());
    if (const auto ec = bufOrErr.getError()) {
        llvm::errs() << "cannot open/read " << path.string() << ": " + ec.message();
        return {};
    }

    const std::unique_ptr<MemoryBuffer>& mb = *bufOrErr;
    std::string buffer;
    buffer.reserve(mb->getBufferSize());
    buffer.assign(mb->getBufferStart(), mb->getBufferSize());
    return buffer;
}

class CompileTest : public testing::Test {
    std::filesystem::path SourceFile;

    void TestBody() override {
        const auto buffer = file_to_string(SourceFile);
        const auto compile_runtime = buffer.find("import") != std::string::npos;
        const auto exitCode = TestUtils::CompileAndRun(SourceFile.string(), buffer, "main", compile_runtime);
        EXPECT_EQ(0, exitCode);
    }

  public:
    explicit CompileTest(const std::filesystem::path& sourceFile)
        : SourceFile(sourceFile) {}
};

std::unordered_map<std::string, std::string> env;

void RegisterTests() {
    auto search_dir = std::filesystem::path{env["PEP_SEARCH_DIR"]};
    search_dir = search_dir.empty() ? absolute(std::filesystem::current_path()) : search_dir;
    if (!exists(search_dir))
        return;
    for (auto entry : std::filesystem::directory_iterator(search_dir)) {
        if (entry.is_directory()) {
            if (auto testSource = entry.path() / "test.pep"; exists(testSource)) {
                auto testName = entry.path().filename().string();
                testing::RegisterTest("CompileTest",
                                      testName.c_str(),
                                      nullptr,
                                      nullptr,
                                      absolute(testSource).string().c_str(),
                                      0,
                                      [=]() -> CompileTest* { return new CompileTest(testSource); });
            }
        }
    }
}

int main(int argc, char** argv) {
    testing::InitGoogleTest(&argc, argv);

    const auto cwd = std::filesystem::current_path();
    const auto dot_env = cwd / ".env";
    if (exists(dot_env)) {
        const auto contents = file_to_string(dot_env);
        for (const auto& line_range : std::ranges::views::split(contents, "\n")) {
            const auto line = std::string{line_range.begin(), line_range.end()};
            const auto pattern = std::regex{"([^=]+)=(.+)"};
            std::smatch match;
            if (std::regex_match(line, match, pattern)) {
                env.emplace(match.str(1), match.str(2));
            }
        }
    }

    GTEST_FLAG_SET(catch_exceptions, false);
    RegisterTests();

    return RUN_ALL_TESTS();
}
