
#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>
#include <iostream>

#include "AST/Parser.h"
#include "Codegen/Codegen.h"
#include "Codegen/ModuleContext.h"
#include "Compiler/Options.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "llvm/Support/Error.h"

namespace pepper {
    class PepperCompiler : public Compiler {
      private:
        std::unique_ptr<Parser> ParserRef;

      public:
        explicit PepperCompiler(const std::string& moduleName) {
            ModuleName = moduleName;

            ParserRef = std::make_unique<Parser>();
        }

        Ref<ast::AST> parse(std::istream& inputStream, const std::string& sourceFile) {
            return ParserRef->parse(inputStream, sourceFile);
        }

        Ref<ModuleContext> compile(const std::string& sourceFile) override {
            std::ifstream sourceStream(sourceFile, std::ios_base::in);
            auto sourcePath = std::filesystem::path(sourceFile);
            return compile(sourceStream, sourcePath.string());
        }

        Ref<ModuleContext> compile(std::istream& sourceStream, const std::string& sourceFile) override {
            SourcePath = sourceFile;
            auto ast = parse(sourceStream, sourceFile);
            if (!ast) {
                Messages::Report<Error>("Failed to parse {0}", sourceFile);
            }

            if (Messages::errors().size()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            Codegen gen(ModuleName, ast);
            auto module = gen.emit();

            if (Messages::errors().size()) {
                throw CompileError("Codegen error(s) encountered, cannot continue");
            }

            std::cout << module->toString() << std::endl;

            auto err = module->verify();
            if (err) {
                Messages::Report<Error>("Module Verification failed: {0}", llvm::toString(std::move(err)));
            }

            if (Messages::errors().size()) {
                throw CompileError("Verification failed, cannot continue");
            }

            return module;
        }
    };

    Ref<Compiler> Compiler::Create(const std::string& moduleName) {
        return Ref<PepperCompiler>::New(moduleName);
    }

} // namespace pepper
