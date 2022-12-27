
#pragma once

#include <memory>

#include "Core/Common.h"
#include "Core/Name.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper::ast {
    class AST;
    class Node;
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
        llvm::Value* maybeCodegen(Ref<N> node) {
            return node ? codegen(node) : nullptr;
        }

        // General builder, normal insertion point
        static Ref<llvm::IRBuilderBase> ir();
        // builder placed at the head of the current block, to allow mem2reg to optimize register mappings
        static Ref<llvm::IRBuilderBase> registers();

        static llvm::Type* resolveType(llvm::Value* value);
        static llvm::Value* read(llvm::Value* value);
        static llvm::Value* zeroValue(llvm::Type* type);

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        llvm::Value* codegen(Ref<ast::Node> node);

        // individual AST -> IR transforms
        llvm::Value* emit(Ref<ast::VariableRef> variableRef);
        llvm::Value* emit(Ref<ast::VariableDef> variableDef);
        llvm::Value* emit(Ref<ast::StringLiteral> stringLiteral);
        llvm::Value* emit(Ref<ast::IntegerLiteral> intLiteral);
        llvm::Value* emit(Ref<ast::FloatLiteral> floatLiteral);
        llvm::Value* emit(Ref<ast::FieldDef> fieldDef);
        llvm::Value* emit(Ref<ast::MemberRef> memberRef);
        llvm::Value* emit(Ref<ast::ThisRef> thisRef);
        llvm::Value* emit(Ref<ast::FunctionDef> functionDef);
        llvm::Value* emit(Ref<ast::Return> ret);
        llvm::Value* emit(Ref<ast::FunctionCall> call);
        llvm::Value* emit(Ref<ast::CompoundAssign> op);
        llvm::Value* emit(Ref<ast::BinaryOp> op);

        Ref<class Struct> emit(Ref<ast::StructDef> structDef);

        void codegenFunction(Ref<class UserFunction> function, Ref<ast::FunctionDef> funcDef);
        Ref<Function> resolveFunction(Ref<ast::FunctionCall> call);
    };

} // namespace pepper
