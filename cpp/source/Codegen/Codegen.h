
#pragma once

#include "Core/Common.h"

namespace pepper::ast {
    class AST;
    class FieldDef;
    class FunctionDef;
    class MemberRef;
    class StructDef;
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
        void emit(Ref<StructDef> structDef);
        void emit(Ref<FieldDef> fieldDef);
        void emit(Ref<MemberRef> memberRef);
        void emit(Ref<ThisRef> thisRef);
        void emit(Ref<FunctionDef> functionDef);
        void emit(Ref<VariableRef> variableRef);
        void emit(Ref<StringLiteral> stringLiteral);
        void emit(Ref<IntegerLiteral> intLiteral);
        void emit(Ref<FloatLiteral> floatLiteral);
        void emit(Ref<BinaryOp> op);
        void emit(Ref<FunctionCall> call);
        void emit(Ref<Return> ret);
    };

} // namespace pepper
