
#include "Compiler/Compiler.h"
#include "Compiler/Options.h"

using namespace pepper;

int main(int argc, const char** argv) {
    auto options = Options::FromCommandLine(argc, argv);
    auto compiler = pepper::Compiler::Create(options);
    compiler->compile();

    return 0;
}
