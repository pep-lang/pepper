
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
    };

} // namespace pepper
