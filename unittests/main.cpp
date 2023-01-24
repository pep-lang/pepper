

#include <filesystem>

#include "Core/Vector.h"
#include "TestUtils.h"
#include "gtest/gtest.h"
#include "llvm/Support/MemoryBuffer.h"

class CompileTest : public testing::Test {
    std::filesystem::path SourceFile;

  public:
    explicit CompileTest(const std::filesystem::path& sourceFile)
        : SourceFile(sourceFile) {}

    void TestBody() override {
        using namespace llvm;

        auto bufOrErr = MemoryBuffer::getFile(SourceFile.string());
        if (auto ec = bufOrErr.getError()) {
            ASSERT_TRUE(false) << "cannot open/read " << SourceFile << ": " + ec.message();
            return;
        }

        std::unique_ptr<MemoryBuffer>& mb = *bufOrErr;
        std::string buffer;
        buffer.reserve(mb->getBufferSize());
        buffer.assign(mb->getBufferStart(), mb->getBufferSize());

        auto exitCode = TestUtils::CompileAndRun(SourceFile.string(), (std::string)buffer, "main");
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
