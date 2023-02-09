
#include "DebugInfo.h"
#include <filesystem>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Sema/Param.h"
#include "Sema/SemaContext.h"
#include "Sema/Struct.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    DebugInfo::DebugInfo(llvm::Module* module, const std::string& sourceFile)
        : Module(module) {
        DI = Ref<llvm::DIBuilder>::New(*module);
        auto primarySourceFile = getSourceFile(sourceFile);
        CompileUnit = DI->createCompileUnit(llvm::dwarf::DW_LANG_C, primarySourceFile, "Pepper Compiler", false, {}, 0);
        pushScope(CompileUnit);
    }

    DebugInfo::~DebugInfo() {
        if (DI) {
            finalize();
        }
    }

    void DebugInfo::finalize() {
        popScope();
        DI->finalize();
        DI.reset();
    }

    void DebugInfo::setSourceLocation(const SourceLocation& source) {
        if (!source.File.empty()) {
            Source = source;
            if (!SourceFiles.lookup(Source.File)) {
                auto sourcePath = std::filesystem::path(Source.File);
                SourceFiles[Source.File] =
                    DI->createFile(sourcePath.filename().string(), sourcePath.parent_path().string());
            }
            if (auto builder = ir())
                builder->SetCurrentDebugLocation(location());
        }
    }

    llvm::DIFile* DebugInfo::getSourceFile(const std::string& sourceFile) {
        auto source = (sourceFile.empty()) ? Source.File : sourceFile;
        if (auto diFile = SourceFiles.lookup(source))
            return diFile;
        auto sourcePath = std::filesystem::path(source);
        auto diFile = SourceFiles[Source.File] =
            DI->createFile(sourcePath.filename().string(), sourcePath.parent_path().string());
        return diFile;
    }

    Ref<llvm::IRBuilderBase> DebugInfo::ir() {
        return SemaContext::ir();
    }

    llvm::DILocation* DebugInfo::location() const {
        return llvm::DILocation::get(ir()->getContext(), Source.Line, Source.Column, localScope());
    }

    llvm::DIScope* DebugInfo::globalScope() const {
        assert(!Stack.empty() && "Global scope requested while no scopes are on the stack");
        return Stack.front();
    }

    uint64_t DebugInfo::sizeOf(const Type* type) const {
        auto llvmType = Types::get(type);
        return Module->getDataLayout().getTypeSizeInBits(llvmType);
    }

    llvm::DIType* DebugInfo::emitBasicType(llvm::StringRef name, const Type* type) {
        auto llvmType = Types::get(type);
        if (llvmType->isVoidTy())
            return nullptr;

        assert(!llvmType->isArrayTy() && !llvmType->isStructTy());
        auto encoding = llvm::dwarf::DW_ATE_unsigned;
        if (llvmType->isFloatingPointTy())
            encoding = llvm::dwarf::DW_ATE_float;
        if (llvmType->isIntegerTy(1))
            encoding = llvm::dwarf::DW_ATE_boolean;
        if (llvmType->isIntegerTy() && type->isSigned())
            encoding = llvm::dwarf::DW_ATE_signed;
        auto diType = DI->createBasicType(name, sizeOf(type), encoding);
        return insertType(type, diType);
    }

    llvm::DILocalVariable* DebugInfo::emitLocalVariable(const Address& value) {
        if (!localScope())
            return nullptr;
        PEP_TRACE(TraceChannel::DebugInfo,
                  "local: {0} {1} {2}: {3}",
                  localScope()->getName(),
                  value.Ty->name(),
                  value.Name,
                  Source.toString());
        auto local = DI->createAutoVariable(
            localScope(), value.Name, getSourceFile(), Source.Line, getOrCreateType(value.Ty.get()), true);
        llvm::SmallVector<uint64_t, 3> diExpr;
        DI->insertDeclare(value.Value, local, DI->createExpression(diExpr), location(), ir()->GetInsertBlock());
        return local;
    }

    llvm::DIGlobalVariableExpression* DebugInfo::emitGlobalVariable(const Address& global) {
        return DI->createGlobalVariableExpression(globalScope(),
                                                  global.Name,
                                                  global.Name,
                                                  getSourceFile(),
                                                  Source.Line,
                                                  getOrCreateType(global.Ty.get()),
                                                  true);
    }

    llvm::DIType* DebugInfo::emitStruct(const Struct* st) {
        // Create an empty struct, then enumerate the fields, then swap them in
        auto structDI = DI->createStructType(localScope(),
                                             st->name(),
                                             getSourceFile(),
                                             Source.Line,
                                             st->size() * 8,
                                             st->align() * 8,
                                             llvm::DINode::FlagPublic | llvm::DINode::FlagNonTrivial,
                                             nullptr,
                                             llvm::DINodeArray());
        // Insert the struct and ref types, in case the struct is self-referential
        insertType(st->structType().get(), structDI);
        insertType(st->refType().get());
        Vector<llvm::Metadata*> elements;
        for (int fieldIdx = 0; fieldIdx < st->fields().size(); ++fieldIdx) {
            auto f = emitField(st, structDI, fieldIdx);
            elements.emplace_back(f);
        }
        auto fields = DI->getOrCreateArray(elements);
        DI->replaceArrays(structDI, fields);
        return structDI;
    }

    llvm::DIType* DebugInfo::emitField(const Struct* st, llvm::DIType* structDI, int fieldIdx) {
        const auto& fields = st->fields();
        const auto& field = fields[fieldIdx];
        auto fieldTy = getOrCreateType(field.Type.get());
        auto llvmType = Types::get(st->structType().get());
        auto structTy = llvm::cast<llvm::StructType>(llvmType);
        auto structLayout = Module->getDataLayout().getStructLayout(structTy);
        auto sizeInBits = sizeOf(field.Type.get());
        auto alignInBits = 0;
        auto offsetInBits = structLayout->getElementOffsetInBits(fieldIdx);

        return DI->createMemberType(localScope(),
                                    field.Name,
                                    getSourceFile(),
                                    Source.Line,
                                    sizeInBits,
                                    alignInBits,
                                    offsetInBits,
                                    llvm::DINode::FlagPublic,
                                    fieldTy);
    }

    llvm::DISubroutineType* DebugInfo::createFunctionType(Function* function) {
        Vector<llvm::Metadata*> elementTypes;
        // first, return type
        auto returnType = getOrCreateType(function->returnType().get());
        elementTypes.emplace_back(returnType);

        for (const auto& param : function->params()) {
            auto paramType = getOrCreateType(param.Type.get());
            elementTypes.emplace_back(paramType);
        }

        return DI->createSubroutineType(DI->getOrCreateTypeArray(elementTypes));
    }

    llvm::DISubprogram* DebugInfo::emitFunction(Function* function) {
        llvm::DINode::DIFlags flags = llvm::DINode::FlagZero;

        if (function->is<Method>() && function->name().ends_with("__acquire") ||
            function->name().ends_with("__release"))
            flags |= llvm::DINode::FlagArtificial;

        auto sp = [&]() {
            // TODO: template parameters when generic functions are supported
            if (function->is<Method>()) {
                return DI->createMethod(localScope(),
                                        function->name(),
                                        function->name(),
                                        getSourceFile(),
                                        Source.Line,
                                        createFunctionType(function),
                                        -1,
                                        0,
                                        nullptr,
                                        llvm::DINode::FlagPrototyped | flags,
                                        llvm::DISubprogram::SPFlagDefinition | llvm::DISubprogram::SPFlagNonvirtual);
            }
            return DI->createFunction(localScope(),
                                      function->name(),
                                      function->name(),
                                      getSourceFile(),
                                      Source.Line,
                                      createFunctionType(function),
                                      Source.Line,
                                      llvm::DINode::FlagPrototyped | flags,
                                      llvm::DISubprogram::SPFlagDefinition);
        }();
        function->function()->setSubprogram(sp);
        return sp;
    }

    llvm::DILocalVariable* DebugInfo::emitParameter(int argIndex, const Address& value) {
        if (!localScope())
            return nullptr;

        llvm::DINode::DIFlags flags = llvm::DINode::FlagZero;
        if (argIndex == 0 && value.Ty->isPointer() && value.Name == "this")
            flags |= llvm::DINode::FlagObjectPointer | llvm::DINode::FlagArtificial;

        // add one to argIndex, DI params are 1-based to account for return type at 0
        llvm::DILocalVariable* local = DI->createParameterVariable(localScope(),
                                                                   value.Name,
                                                                   argIndex + 1,
                                                                   getSourceFile(),
                                                                   Source.Line,
                                                                   getOrCreateType(value.Ty.get()),
                                                                   true,
                                                                   flags);
        DI->insertDeclare(value.Value, local, DI->createExpression(), location(), ir()->GetInsertBlock());
        return local;
    }

    void DebugInfo::pushScope(llvm::DIScope* newScope) {
        Stack.push_back(newScope);
        if (Stack.size() > 1)
            setSourceLocation(Source); // force the source location into the builder
    }

    void DebugInfo::popScope() {
        auto scope = Stack.pop_back_val();
        if (scope && llvm::isa<llvm::DISubprogram>(scope)) {
            auto sp = llvm::cast<llvm::DISubprogram>(scope);
            DI->finalizeSubprogram(sp);
        }
    }

    llvm::DIScope* DebugInfo::localScope() const {
        return Stack.back();
    }

    llvm::DIType* DebugInfo::getStruct(const Struct* st) {
        auto it = Types.find(st->structType().get());
        if (it != Types.end()) {
            auto& diTy = it->getSecond();
            return diTy ? cast<llvm::DIType>(diTy) : nullptr;
        }
        return nullptr;
    }

    llvm::DIType* DebugInfo::getOrCreateType(const Type* type) {
        auto it = Types.find(type);
        if (it != Types.end()) {
            auto& diTy = it->getSecond();
            return diTy ? cast<llvm::DIType>(diTy) : nullptr;
        }

        return insertType(type);
    }

    llvm::DIType* DebugInfo::insertType(const Type* type, llvm::DIType* diType) {
        if (!diType) {
            if (!type->isPointer() && !type->isStruct()) {
                diType = emitBasicType(type->name(), type);
            } else if (auto ptrType = type->as<PointerType>()) {
                auto pointee = ptrType->pointeeType();
                llvm::DIType* pointeeDI = getOrCreateType(pointee.get());
                diType = DI->createPointerType(pointeeDI, sizeOf(ptrType));
            } else {
                // TODO create new type and insert it
                throw InternalCompilerError("Unable to map type for debugging: {0}", type->name());
            }
        }

        Types[type].reset(diType);
        return diType;
    }
} // namespace pepper
