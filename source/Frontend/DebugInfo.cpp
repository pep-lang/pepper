
#include "Frontend/DebugInfo.h"
#include <filesystem>

#include "Core/Exceptions.h"
#include "Frontend/Context.h"
#include "Frontend/Param.h"
#include "Frontend/Struct.h"
#include "llvm/IR/LLVMContext.h"

namespace pepper {
    DebugInfo::DebugInfo(llvm::Module* module, const std::string& sourceFile)
        : Module(module) {
        DI = Ref<llvm::DIBuilder>::New(*module);
        auto sourcePath = std::filesystem::path(sourceFile);
        SourceFile = DI->createFile(sourcePath.filename().string(), sourcePath.parent_path().string());
        CompileUnit = DI->createCompileUnit(llvm::dwarf::DW_LANG_C, SourceFile, "Pepper Compiler", false, {}, 0);
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
        Source = source;
        if (auto builder = ir())
            builder->SetCurrentDebugLocation(
                llvm::DILocation::get(builder->getContext(), Source.Line, Source.Column, localScope()));
    }

    Ref<llvm::IRBuilderBase> DebugInfo::ir() {
        return Context::ir();
    }

    llvm::DILocation* DebugInfo::location() const {
        return llvm::DILocation::get(ir()->getContext(), Source.Line, 0, localScope());
    }

    llvm::DIScope* DebugInfo::globalScope() const {
        assert(!Stack.empty() && "Global scope requested while no scopes are on the stack");
        return Stack.front();
    }

    uint64_t DebugInfo::sizeOf(const Type* type) const {
        return Module->getDataLayout().getTypeSizeInBits(type->llvmType());
    }

    llvm::DIType* DebugInfo::emitBasicType(llvm::StringRef name, const Type* type) {
        if (type->llvmType()->isVoidTy())
            return nullptr;

        assert(!type->llvmType()->isArrayTy() && !type->llvmType()->isStructTy());
        auto encoding = llvm::dwarf::DW_ATE_unsigned;
        if (type->llvmType()->isFloatingPointTy())
            encoding = llvm::dwarf::DW_ATE_float;
        if (type->llvmType()->isIntegerTy(1))
            encoding = llvm::dwarf::DW_ATE_boolean;
        if (type->llvmType()->isIntegerTy() && type->isSigned())
            encoding = llvm::dwarf::DW_ATE_signed;
        auto diType = DI->createBasicType(name, sizeOf(type), encoding);
        return insertType(type, diType);
    }

    llvm::DILocalVariable* DebugInfo::emitLocalVariable(const Value& value) {
        auto local = DI->createAutoVariable(
            localScope(), value.Name, SourceFile, Source.Line, getOrCreateType(value.Ty.get()), true);
        llvm::SmallVector<uint64_t, 13> diExpr;
        // Allow debugger to use the pointee as the value
        if (value.Ty->isPointer() && value.Ty.as<PointerType>()->pointeeType()->isStruct()) {
            diExpr.emplace_back(llvm::dwarf::DW_OP_deref);
        }
        DI->insertDeclare(value.V, local, DI->createExpression(diExpr), location(), ir()->GetInsertBlock());
        return local;
    }

    llvm::DIGlobalVariableExpression* DebugInfo::emitGlobalVariable(const Value& global) {
        return DI->createGlobalVariableExpression(
            globalScope(), global.Name, global.Name, SourceFile, Source.Line, getOrCreateType(global.Ty.get()), true);
    }

    llvm::DILocalVariable* DebugInfo::emitParameter(int argIndex, const Value& value) {
        // add one to argIndex, DI params are 1-based
        llvm::DILocalVariable* local = DI->createParameterVariable(
            localScope(), value.Name, argIndex + 1, SourceFile, Source.Line, getOrCreateType(value.Ty.get()), true);
        DI->insertDeclare(value.V, local, DI->createExpression(), location(), ir()->GetInsertBlock());
        return local;
    }

    llvm::DIType* DebugInfo::emitStruct(const Struct* st) {
        // Create an empty struct, then enumerate the fields, then swap them in
        auto structDI = DI->createStructType(localScope(),
                                             st->name(),
                                             SourceFile,
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
        auto structTy = llvm::cast<llvm::StructType>(st->structType()->llvmType());
        auto structLayout = Module->getDataLayout().getStructLayout(structTy);
        auto offset = structLayout->getElementOffsetInBits(fieldIdx);

        return DI->createMemberType(localScope(),
                                    field.Name,
                                    SourceFile,
                                    Source.Line,
                                    sizeOf(field.Type.get()),
                                    0,
                                    offset,
                                    llvm::DINode::FlagPublic,
                                    structDI);
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
        auto sp = [&]() {
            // TODO: template parameters when generic functions are supported
            if (function->is<Method>()) {
                return DI->createMethod(localScope(),
                                        function->name(),
                                        function->name(),
                                        SourceFile,
                                        Source.Line,
                                        createFunctionType(function),
                                        -1,
                                        0,
                                        nullptr,
                                        llvm::DINode::FlagPrototyped,
                                        llvm::DISubprogram::SPFlagDefinition | llvm::DISubprogram::SPFlagNonvirtual);
            }
            return DI->createFunction(localScope(),
                                      function->name(),
                                      function->name(),
                                      SourceFile,
                                      Source.Line,
                                      createFunctionType(function),
                                      Source.Line,
                                      llvm::DINode::FlagPrototyped,
                                      llvm::DISubprogram::SPFlagDefinition);
        }();
        function->function()->setSubprogram(sp);
        return sp;
    }

    void DebugInfo::pushScope(llvm::DIScope* newScope) {
        Stack.push_back(newScope);
    }

    void DebugInfo::popScope() {
        auto scope = Stack.pop_back_val();
        if (llvm::isa<llvm::DISubprogram>(scope)) {
            auto sp = llvm::cast<llvm::DISubprogram>(scope);
            DI->finalizeSubprogram(sp);
        }
    }

    llvm::DIScope* DebugInfo::localScope() const {
        return Stack.back();
    }

    llvm::DIType* DebugInfo::getOrCreateType(const Type* type) {
        auto it = Types.find(type);
        if (it != Types.end()) {
            auto& diTy = it->getSecond();
            return diTy ? cast<llvm::DIType>(diTy) : nullptr;
        }

        llvm::DIType* newTy = insertType(type);
        Types[type].reset(newTy);
        return newTy;
    }

    llvm::DIType* DebugInfo::insertType(const Type* type, llvm::DIType* diType) {
        if (!diType) {
            if (!type->isPointer() && !type->isStruct()) {
                diType = emitBasicType(type->name(), type);
            } else if (auto ptrType = type->as<PointerType>()) {
                auto pointee = ptrType->pointeeType();
                llvm::DIType* pointeeDI = getOrCreateType(pointee.get());
                if (pointee->isStruct())
                    diType = DI->createObjectPointerType(pointeeDI);
                else
                    diType = DI->createPointerType(pointeeDI, sizeOf(ptrType), 0, llvm::None, ptrType->name());
            } else if (auto structType = type->as<StructType>()) {
                assert(false && "Structs should be registered with DebugInfo before pointers to them are encountered");
            } else {
                // TODO create new type and insert it
                throw InternalCompilerError("Unable to map type for debugging: {0}", type->name());
            }
        }

        Types[type].reset(diType);
        return diType;
    }
} // namespace pepper
