
#pragma once

#include "Core/Common.h"

namespace pepper::ast {
    class AST;
    class FieldDef;
    class FunctionCall;
    class FunctionDef;
    class MemberRef;
    class StructDef;
    class ThisRef;
    class VariableRef;
    class VariableDef;
    class StringLiteral;
    class FloatLiteral;
    class IntegerLiteral;
    class BinaryOp;
    class Return;
} // namespace pepper::ast

namespace pepper {
    class Codegen {
      protected:
        Ref<ast::AST> Tree;

      public:
        Codegen(const Ref<ast::AST> tree)
            : Tree(tree) {
        }

        void emit();

      protected:
        void emit(Ref<ast::StructDef> structDef);
        void emit(Ref<ast::FieldDef> fieldDef);
        void emit(Ref<ast::MemberRef> memberRef);
        void emit(Ref<ast::ThisRef> thisRef);
        void emit(Ref<ast::FunctionDef> functionDef);
        void emit(Ref<ast::VariableRef> variableRef);
        void emit(Ref<ast::VariableDef> variableDef);
        void emit(Ref<ast::StringLiteral> stringLiteral);
        void emit(Ref<ast::IntegerLiteral> intLiteral);
        void emit(Ref<ast::FloatLiteral> floatLiteral);
        void emit(Ref<ast::BinaryOp> op);
        void emit(Ref<ast::FunctionCall> call);
        void emit(Ref<ast::Return> ret);
    };

} // namespace pepper
