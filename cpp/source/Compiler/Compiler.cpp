
#include "Compiler/Compiler.h"

#include "Codegen/Codegen.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Options.h"
#include "Compiler/Parser.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_os_ostream.h"
#include "llvm/Support/raw_ostream.h"
#include <filesystem>
#include <fstream>
#include <iostream>

namespace pepper {
    class PepperCompiler : public Compiler {
      private:
        std::unique_ptr<Context> Ctx;
        std::unique_ptr<Parser> ParserRef;
        std::vector<Ref<Warning>> Warnings;
        std::vector<Ref<Error>> Errors;

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

        Ref<ast::AST> parse(std::istream& inputStream, const std::string& sourceFile) {
            try {
                return ParserRef->parse(inputStream, sourceFile);
            } catch (const std::exception& e) {
                std::cerr << e.what() << '\n';
            }

            return nullptr;
        }

        llvm::Module* compile(const std::string& sourceFile) override {
            std::ifstream sourceStream(sourceFile, std::ios_base::in);
            auto sourcePath = std::filesystem::path(sourceFile);
            return compile(sourceStream, sourcePath.string());
        }

        llvm::Module* compile(std::istream& sourceStream, const std::string& sourceFile) override {
            auto ast = parse(sourceStream, sourceFile);
            if (!ast) {
                Report<Error>("Failed to parse {0}", sourceFile);
            }

            if (Errors.size()) {
                throw CompileError("Parse error(s) encountered, cannot continue");
            }

            Codegen gen(ast);
            gen.emit();

            if (Errors.size()) {
                throw CompileError("Codegen error(s) encountered, cannot continue");
            }

            llvm::raw_os_ostream out(std::cout);
            Ctx->module()->print(out, nullptr, false, true);

            std::string verifyOutput;
            llvm::raw_string_ostream vout(verifyOutput);
            bool debugInfoBroken = false;
            if (llvm::verifyModule(*Ctx->module(), &vout, &debugInfoBroken)) {
                Report<Error>("Module Verification failed: {0}", verifyOutput);
            }

            if (Errors.size()) {
                throw CompileError("Verification failed, cannot continue");
            }

            return Context::get().module();
        }

        void report(Ref<Message> msg) override {
            if (msg->is<Warning>()) {
                Warnings.push_back(msg.as<Warning>());
                std::cout << msg->message();
            }

            if (msg->is<Error>()) {
                Errors.push_back(msg.as<Error>());
                std::cerr << msg->message();
            }
        }
    };

    Ref<Compiler> Compiler::Create(const std::string& moduleName) {
        return Ref<PepperCompiler>::New(moduleName);
    }

} // namespace pepper
