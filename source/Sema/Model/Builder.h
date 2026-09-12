

#pragma once

#include "Core/Ident.h"
#include "Core/SourceLocation.h"
#include "Core/Tracer.h"
#include "Sema/Model/Nodes.h"

namespace pepper::sema {
    struct ParserTracer;

    class Builder {
      public:
        ParserTracer* tracer = nullptr;

        Builder(ParserTracer* trace)
            : tracer(trace) {}

        virtual ~Builder() = default;

        virtual SourceLocation location() const = 0;

        template <typename T>
        T* target_as() {
            return target() ? target()->to<T>() : nullptr;
        }

        virtual ScopeTarget* target() = 0;

        virtual void begin_struct(StructDef* st) = 0;
        virtual void end_struct() = 0;

        virtual void begin_trait(TraitDecl* trait) = 0;
        virtual void end_trait() = 0;

        virtual void begin_extension(ExtensionDef* ext) = 0;
        virtual void end_extension() = 0;

        virtual void begin_function(FunctionNode* func) = 0;
        virtual void end_function() = 0;

        virtual void begin_block(Block* block) = 0;
        virtual void end_block() = 0;
        virtual Block* block() const = 0;

        virtual void begin_scope(const Ident& name = "Anonymous") = 0;
        virtual void end_scope() = 0;

        virtual void push_rvalue(Node* value) = 0;
        virtual Node* pop_rvalue() = 0;
        virtual Node* peek_rvalue(unsigned int idx) const = 0;

        virtual void push_lvalue(Node* value) = 0;
        virtual Node* pop_lvalue() = 0;
        virtual Node* peek_lvalue(unsigned int idx) const = 0;

        virtual void symbol(VariableDef* var) = 0;
        virtual void insert(Node* expr) = 0;
        virtual void import(Import* import) = 0;
    };
} // namespace pepper::sema
