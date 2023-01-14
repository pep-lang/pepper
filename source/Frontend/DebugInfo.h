
#pragma once

#include "CodeGen/Value.h"
#include "Core/Common.h"
#include "Core/SourceLocation.h"
#include "Core/Vector.h"
#include "Frontend/Function.h"
#include "Frontend/Struct.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    class Struct;
    class Type;
    class Function;

    class DebugInfo {
        llvm::Module* Module;
        Ref<llvm::DIBuilder> DI;
        llvm::DICompileUnit* CompileUnit;
        llvm::DIFile* SourceFile;
        Vector<llvm::DIScope*> Stack;
        llvm::DenseMap<const Type*, llvm::TrackingMDRef> Types;

        SourceLocation Source;

        DebugInfo(const DebugInfo&) = delete;
        DebugInfo(DebugInfo&&) = delete;

      public:
        DebugInfo(llvm::Module* module, const std::string& sourceFile);
        ~DebugInfo();

        void setSourceLocation(const SourceLocation& source);

        const SourceLocation& getSourceLocation() const {
            return Source;
        }

        // void emitSourceLocation(const SourceLocation& source);

        void finalize();

        llvm::DIType* emitBasicType(llvm::StringRef name, const Type* type);
        llvm::DILocalVariable* emitLocalVariable(const Value& value);
        llvm::DIType* emitStruct(const Struct* st);
        llvm::DIType* emitField(const Struct* st, llvm::DIType* structDI, int fieldIdx);
        llvm::DISubprogram* emitFunction(Function* function);
        llvm::DILocalVariable* emitParameter(int argIndex, const Value& param);
        llvm::DIGlobalVariableExpression* emitGlobalVariable(const Value& global);

        void pushScope(llvm::DIScope* newScope);
        void popScope();
        llvm::DIScope* localScope() const;
        llvm::DIScope* globalScope() const;

      private:
        llvm::DIType* getOrCreateType(const Type* type);
        llvm::DIType* insertType(const Type* type, llvm::DIType* diType = nullptr);
        llvm::DISubroutineType* createFunctionType(Function* function);
        static Ref<llvm::IRBuilderBase> ir();
        llvm::DILocation* location() const;
        uint64_t sizeOf(const Type* type) const;
    };
} // namespace pepper
