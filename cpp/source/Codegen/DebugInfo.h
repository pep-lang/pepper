
#pragma once

#include <unordered_map>

#include "Codegen/Function.h"
#include "Codegen/Struct.h"
#include "Core/Common.h"
#include "Core/SourceLocation.h"
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
        llvm::SmallVector<llvm::DIScope*> Stack;
        std::unordered_map<llvm::Type*, llvm::DIType*> Types;

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

        void finalize() {
            DI->finalize();
            DI.reset();
        }

        void newBasicType(llvm::StringRef name, Ref<Type> type);
        void newVariable(llvm::StringRef name, llvm::Value* value);
        void newParameter(llvm::StringRef name, int argIndex, llvm::Value* value);
        void newStruct(llvm::StringRef name, Struct* st);
        void newFunction(llvm::StringRef name, llvm::Function* function);
        void pushScope(llvm::DIScope* newScope);
        void popScope();
        llvm::DIScope* scope() const;
    };
} // namespace pepper
