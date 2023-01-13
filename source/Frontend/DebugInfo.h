
#pragma once

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

        void setSourceLocation(const SourceLocation& source) {
            Source = source;
        }

        // void emitSourceLocation(const SourceLocation& source);

        void finalize();

        llvm::DIType* newBasicType(llvm::StringRef name, Ref<Type> type);
        llvm::DIType* newVariable(llvm::StringRef name, llvm::Value* value);
        llvm::DIType* newStruct(llvm::StringRef name, Struct* st);
        llvm::DIType* newFunction(llvm::StringRef name, llvm::Function* function);
        void newParameter(llvm::StringRef name, int argIndex, llvm::Value* value);

        void pushScope(llvm::DIScope* newScope);
        void popScope();
        llvm::DIScope* scope() const;

        llvm::DIType* getOrCreateType(const Type* type);
        llvm::DIType* insertType(const Type* type, llvm::DIType* diType = nullptr);
    };
} // namespace pepper
