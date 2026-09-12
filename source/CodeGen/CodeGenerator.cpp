
#include "CodeGenerator.h"

#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Compiler/Options.h"
#include "Core/Messages.h"

namespace pepper {

    CodeGenerator::CodeGenerator(
        CodeGenerator::Type backendType, SemaContext& context, const Ident& name, const std::string& sourcePath) {
        switch (backendType) {
            case Type::LLVM: {
                auto module = Ref<LLVMModuleGenerator>::create(context, name, sourcePath);
                backend = std::make_unique<LLVMCodeGenerator>(module);
                break;
            }
            case Type::Cpp:
                break;
        }
    }

    void CodeGenerator::generate(Ref<sema::Module> tree, Ref<Options> options) {
        PEP_TRACE(TraceChannel::Codegen, "Code generation:");
        PEP_TRACE(TraceChannel::Codegen, "Instantiation pass:");
        backend->generate(tree, options);
    }

    std::string CodeGenerator::get_object_file_path() const {
        return backend->get_object_file_path();
    }
} // namespace pepper
