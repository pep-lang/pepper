
#pragma once

#include <memory>

#include "Core/Common.h"
#include "Core/Name.h"

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
    class Context;
    class ModuleContext;

    class Codegen {
      protected:
        Ref<ast::AST> Tree;
        Ref<ModuleContext> Ctx;

      public:
        Codegen(const Name& moduleName, Ref<ast::AST> tree);

        Ref<ModuleContext> emit();
    };

} // namespace pepper
