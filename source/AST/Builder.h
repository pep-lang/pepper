//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "AST/Nodes.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"

namespace pepper::ast {
    class Builder {
      public:
        SourceLocation Source;

        virtual ~Builder() = default;

        template <typename T>
        T* targetAs() {
            return target() ? target()->to<T>() : nullptr;
        }

        virtual ScopeTarget* target() = 0;

        virtual void beginStruct(StructDef* st) = 0;
        virtual void endStruct() = 0;

        virtual void beginTrait(TraitDecl* trait) = 0;
        virtual void endTrait() = 0;

        virtual void beginExtension(ExtensionDef* ext) = 0;
        virtual void endExtension() = 0;

        virtual void beginFunction(FunctionNode* func) = 0;
        virtual void endFunction() = 0;

        virtual void beginBlock(Block* block) = 0;
        virtual void endBlock() = 0;
        virtual Block* block() const = 0;

        virtual void beginScope(const Ident& name = "Anonymous") = 0;
        virtual void endScope() = 0;

        virtual void pushRValue(Node* value) = 0;
        virtual Node* popRValue() = 0;
        virtual Node* peekRValue(unsigned int idx) const = 0;

        virtual void pushLValue(Node* value) = 0;
        virtual Node* popLValue() = 0;
        virtual Node* peekLValue(unsigned int idx) const = 0;

        virtual void symbol(VariableDef* var) = 0;
        virtual void insert(Node* expr) = 0;
        virtual void import(Import* import) = 0;

        virtual void trace(const Node* node) const = 0;
    };
} // namespace pepper::ast
