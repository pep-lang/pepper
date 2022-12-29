
#pragma once

#include <memory>

#include "Codegen/IR/Value.h"
#include "Core/Common.h"
#include "Core/Name.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper::ast {
    class AST;
    class Node;
    class Assign;
    class CompoundAssign;
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
    class Branch;
} // namespace pepper::ast

namespace pepper {
    class Context;
    class ModuleContext;
    class Function;

    class Codegen {
      protected:
        Ref<ast::AST> Tree;
        Ref<Context> Ctx;
        Ref<ModuleContext> Module;

      public:
        Codegen(const Name& moduleName, Ref<ast::AST> tree);

        // entry point to codegen, runs all the roots of the AST and generates them
        Ref<ModuleContext> emit();

      protected:
        template <typename N>
        Value maybeCodegen(Ref<N> node) {
            return node ? codegen(node) : Value::Null();
        }

        // General builder, normal insertion point
        static Ref<llvm::IRBuilderBase> ir();
        // builder placed at the head of the current block, to allow mem2reg to optimize register mappings
        static Ref<llvm::IRBuilderBase> registers();

        static llvm::Type* resolveType(Value value);
        static Value read(Value value);
        static Value zeroValue(Ref<TypeInfo> type);

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        Value codegen(Ref<ast::Node> node);

        // individual AST -> IR transforms
        Value emit(Ref<ast::VariableRef> variableRef);
        Value emit(Ref<ast::VariableDef> variableDef);
        Value emit(Ref<ast::StringLiteral> stringLiteral);
        Value emit(Ref<ast::IntegerLiteral> intLiteral);
        Value emit(Ref<ast::FloatLiteral> floatLiteral);
        Value emit(Ref<ast::FieldDef> fieldDef);
        Value emit(Ref<ast::MemberRef> memberRef);
        Value emit(Ref<ast::ThisRef> thisRef);
        Value emit(Ref<ast::FunctionDef> functionDef);
        Value emit(Ref<ast::Return> ret);
        Value emit(Ref<ast::FunctionCall> call);
        Value emit(Ref<ast::Assign> op);
        Value emit(Ref<ast::CompoundAssign> op);
        Value emit(Ref<ast::BinaryOp> op);
        Value emit(Ref<ast::Branch> branch);

        Ref<class Struct> emit(Ref<ast::StructDef> structDef);

        void codegenFunction(Ref<class UserFunction> function, Ref<ast::FunctionDef> funcDef);
        Ref<Function> resolveFunction(Ref<ast::FunctionCall> call);
    };

} // namespace pepper
