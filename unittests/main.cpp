

#include <filesystem>

#include "gtest/gtest.h"
#include "TestUtils.h"
#include "llvm/Support/FileSystem.h"

class CompileTest : public testing::Test {
    std::filesystem::path SourceFile;

  public:
    explicit CompileTest(const std::filesystem::path& sourceFile)
        : SourceFile(sourceFile) {}

    void TestBody() override {
        using namespace llvm::sys;
        int fd = 0;
        auto opened = fs::openFileForRead(SourceFile.string(), fd);
        ASSERT_TRUE(!opened) << "Failed to open source file: " << opened.message();
        llvm::SmallString<fs::DefaultReadChunkSize> buffer;
        auto file = fs::convertFDToNativeFile(fd);
        auto read = fs::readNativeFile(file, buffer);
        ASSERT_TRUE(!!read) << "Failed to read source file: " << llvm::toString(read.takeError());

        auto exitCode = TestUtils::CompileAndRun(SourceFile.string(), (std::string)buffer);
        EXPECT_EQ(0, exitCode);
    }
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
