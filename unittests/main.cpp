

#include <filesystem>

#include "gtest/gtest.h"

class CompileTest : public testing::Test {
    std::filesystem::path SourceFile;

  public:
    explicit CompileTest(const std::filesystem::path& sourceFile)
        : SourceFile(sourceFile) {}

    void TestBody() override {}
};

void RegisterTests() {
    auto sourceDir = absolute(std::filesystem::current_path() / "tests");
    if (!exists(sourceDir))
        return;
    for (auto entry : std::filesystem::directory_iterator(sourceDir)) {
        if (entry.is_directory()) {
            auto testSource = entry.path() / "test.pep";
            if (exists(testSource)) {
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

    RegisterTests();

    return RUN_ALL_TESTS();
}
