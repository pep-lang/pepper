
#pragma once

#include <memory>

#include "Compiler/Options.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Sema/Model/Module.h"
#include "Sema/SemaContext.h"

namespace pepper {
    struct ICodeGenerator {
        virtual ~ICodeGenerator() = default;
        // entry point to codegen, runs all the roots of the AST and generates them
        virtual void generate(Ref<sema::Module> parseTree, Ref<Options> options) = 0;
        virtual std::string get_object_file_path() const = 0;
    };

    class CodeGenerator {
      public:
        enum class Type : uint8_t {
            LLVM,
            Cpp,
        };

        CodeGenerator(Type backendType, SemaContext& context, const Ident& name, const std::string& sourcePath = "");

        void generate(Ref<sema::Module> parseTree, Ref<Options> options);
        std::string get_object_file_path() const;

      private:
        std::unique_ptr<ICodeGenerator> backend;
    };

} // namespace pepper
