
#include "Codegen/DebugInfo.h"

#include "Codegen/Param.h"
#include "Codegen/Struct.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    DebugInfo::DebugInfo(llvm::Module* module, const std::string& sourceFile)
        : Module(module) {
        DI = Ref<llvm::DIBuilder>::New(*module);
        SourceFile = DI->createFile(sourceFile, ".");
        CompileUnit = DI->createCompileUnit(llvm::dwarf::DW_LANG_C, SourceFile, "Pepper Compiler", false, "", 0);
        pushScope(CompileUnit);
    }

    DebugInfo::~DebugInfo() {
        if (DI) {
            finalize();
        }
    }

    void DebugInfo::newBasicType(llvm::StringRef name, Ref<Type> type) {
        auto sizeInBits = Module->getDataLayout().getTypeSizeInBits(*type);
        assert(!type->llvmType()->isArrayTy() && !type->llvmType()->isStructTy());
        auto encoding = llvm::dwarf::DW_ATE_unsigned;
        if (type->llvmType()->isFloatingPointTy())
            encoding = llvm::dwarf::DW_ATE_float;
        // DI->createBasicType(name, sizeInBits, llvm::dwarf::DW_ATE)
    }

    void DebugInfo::newVariable(llvm::StringRef name, llvm::Value* value) {
        // DI->createAutoVariable(scope(), name, SourceFile, Source.Line, value->getType());
    }

    void DebugInfo::newParameter(llvm::StringRef name, int argIndex, llvm::Value* value) {
        // DI->createParameterVariable(scope(), name, argIndex, SourceFile, Source.Line, value->getType());
    }

    void DebugInfo::newStruct(llvm::StringRef name, Struct* st) {
        /* llvm::SmallVector<llvm::Metadata*> fields;
         for (const auto& field : st->fields) {
             field.
         }
         DI->createStructType(scope(),
                              name,
                              SourceFile,
                              Source.Line,
                              st->size() * 8,
                              st->align() * 8,
                              llvm::DINode::FlagPublic | llvm::DINode::FlagNonTrivial,
                              nullptr);*/
    }

    void DebugInfo::newFunction(llvm::StringRef name, llvm::Function* function) {
    }

    void DebugInfo::pushScope(llvm::DIScope* newScope) {
        Stack.push_back(newScope);
    }

    void DebugInfo::popScope() {
    }

    llvm::DIScope* DebugInfo::scope() const {
        return Stack.back();
    }

} // namespace pepper
