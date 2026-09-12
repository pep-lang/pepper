
#include "Compiler/Compiler.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"

using namespace pepper;

int main(int argc, const char** argv) {
    try {
        auto options = Options::from_command_line(argc, argv);
        auto compiler = Compiler::Create(options);
        compiler->compile();
        compiler->link();
    } catch (std::exception& ex) {
        llvm::errs() << ex.what() << "\n";
        llvm::errs() << "Errors encountered, compilation failed"
                     << "\n";
        return -1;
    }

    return 0;
}
