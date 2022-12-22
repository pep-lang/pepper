
#include "Compiler/Compiler.h"

#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Options.h"
#include "Compiler/Parser.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/TargetSelect.h"
#include <filesystem>
#include <fstream>
#include <iostream>

namespace pepper {
    class PepperCompiler : public Compiler {
      private:
        std::unique_ptr<Context> Ctx;
        std::unique_ptr<Parser> ParserRef;

      public:
        explicit PepperCompiler(const std::string& moduleName) {
            llvm::InitializeNativeTarget();
            llvm::InitializeNativeTargetAsmPrinter();
            llvm::InitializeNativeTargetAsmParser();

            Ctx = std::make_unique<Context>(moduleName);
            ParserRef = std::make_unique<Parser>();
        }

        [[nodiscard]] Context& context() const override {
            return *Ctx;
        }

        bool parse(std::istream& inputStream, const std::string& sourceFile) {
            try {
                ParserRef->parse(inputStream, sourceFile);
            } catch (const std::exception& e) {
                std::cerr << e.what() << '\n';
                return false;
            }

            return true;
        }

        llvm::Module* compile(const std::string& sourceFile) override {
            std::ifstream sourceStream(sourceFile, std::ios_base::in);
            auto sourcePath = std::filesystem::path(sourceFile);
            return compile(sourceStream, sourcePath.string());
        }

        llvm::Module* compile(std::istream& sourceStream, const std::string& sourceFile) override {
            if (!parse(sourceStream, sourceFile)) {
                throw CompileError("Failed to parse {0}", sourceFile);
            }
            Ctx->module()->dump();
            return Context::get().module();
        }
    };

    Ref<Compiler> Compiler::Create(const std::string& moduleName) {
        return Ref<PepperCompiler>::create(moduleName);
    }

} // namespace pepper
