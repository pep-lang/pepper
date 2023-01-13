
#include "Frontend/DebugInfo.h"
#include <filesystem>

#include "Frontend/Param.h"
#include "Frontend/Struct.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    DebugInfo::DebugInfo(llvm::Module* module, const std::string& sourceFile)
        : Module(module) {
        DI = Ref<llvm::DIBuilder>::New(*module);
        auto sourcePath = std::filesystem::path(sourceFile);
        SourceFile = DI->createFile(sourcePath.filename().string(), sourcePath.parent_path().string());
        CompileUnit = DI->createCompileUnit(llvm::dwarf::DW_LANG_C, SourceFile, "Pepper Compiler", false, "", 0);
        pushScope(CompileUnit);
    }

    DebugInfo::~DebugInfo() {
        if (DI) {
            finalize();
        }
    }

    void DebugInfo::finalize() {
        // DI->finalize();
        DI.reset();
    }

    llvm::DIType* DebugInfo::newBasicType(llvm::StringRef name, Ref<Type> type) {
        auto sizeInBits = Module->getDataLayout().getTypeSizeInBits(*type);
        assert(!type->llvmType()->isArrayTy() && !type->llvmType()->isStructTy());
        auto encoding = llvm::dwarf::DW_ATE_unsigned;
        if (type->llvmType()->isFloatingPointTy())
            encoding = llvm::dwarf::DW_ATE_float;
        if (type->llvmType()->isIntegerTy(1))
            encoding = llvm::dwarf::DW_ATE_boolean;
        if (type->llvmType()->isIntegerTy() && type->isSigned())
            encoding = llvm::dwarf::DW_ATE_signed;
        auto diType = DI->createBasicType(name, sizeInBits, encoding);
        return insertType(type.get(), diType);
    }

    llvm::DIType* DebugInfo::newVariable(llvm::StringRef name, llvm::Value* value) {
        // DI->createAutoVariable(scope(), name, SourceFile, Source.Line, value->getType());
        return nullptr;
    }

    void DebugInfo::newParameter(llvm::StringRef name, int argIndex, llvm::Value* value) {
        // DI->createParameterVariable(scope(), name, argIndex, SourceFile, Source.Line, value->getType());
    }

    llvm::DIType* DebugInfo::newStruct(llvm::StringRef name, Struct* st) {
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
        return nullptr;
    }

    llvm::DIType* DebugInfo::newFunction(llvm::StringRef name, llvm::Function* function) {
        return nullptr;
    }

    void DebugInfo::pushScope(llvm::DIScope* newScope) {
        Stack.push_back(newScope);
    }

    void DebugInfo::popScope() {
    }

    llvm::DIScope* DebugInfo::scope() const {
        return Stack.back();
    }

    llvm::DIType* DebugInfo::getOrCreateType(const Type* type) {
        auto it = Types.find(type);
        if (it != Types.end()) {
            auto& diTy = it->getSecond();
            return cast<llvm::DIType>(diTy);
        }

        llvm::DIType* newTy = insertType(type);
        Types[type].reset(newTy);
        return newTy;
    }

    llvm::DIType* DebugInfo::insertType(const Type* type, llvm::DIType* diType) {
        if (diType) {
            Types[type].reset(diType);
            return diType;
        }

        // TODO create new type and insert it
        return nullptr;
    }
} // namespace pepper
