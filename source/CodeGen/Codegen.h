
#pragma once

#include <memory>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Frontend/ModuleContext.h"
#include "Frontend/Scope.h"
#include "Value.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    class Codegen {
      protected:
        Ref<ModuleContext> Module;

      public:
        Codegen(Ref<ModuleContext> module);

        // entry point to codegen, runs all the roots of the AST and generates them
        void generate(Ref<ast::AST> parseTree);

      protected:
        template <typename N>
        Value maybeCodegen(Ref<N> node) {
            return node ? codegen(node) : Value::Null();
        }

        static Ref<Scope> locals();
        static Ref<Scope> globals();
        void pushFunction(Ref<UserFunction> function);
        void pushScope(const Ident& name);
        void popScope();

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        Value codegen(Ref<ast::Node> node);

        // individual AST -> IR transforms
        Value emit(Ref<ast::SymbolRef> variableRef);
        Value emit(Ref<ast::VariableDef> variableDef);
        Value emit(Ref<ast::ThisDef> thisDef);
        Value emit(Ref<ast::PointerLiteral> pointerLiteral);
        Value emit(Ref<ast::StringLiteral> stringLiteral);
        Value emit(Ref<ast::IntegerLiteral> intLiteral);
        Value emit(Ref<ast::FloatLiteral> floatLiteral);
        Value emit(Ref<ast::BoolLiteral> boolLiteral);
        Value emit(Ref<ast::FieldDef> fieldDef);
        Value emit(Ref<ast::MemberRef> memberRef);
        Value emit(Ref<ast::ThisRef> thisRef);
        Value emit(Ref<ast::FunctionDef> functionDef);
        Value emit(Ref<ast::Return> ret);
        Value emit(Ref<ast::FunctionCall> call);
        Value emit(Ref<ast::MethodCall> call);
        Value emit(Ref<ast::Assign> op);
        Value emit(Ref<ast::CompoundAssign> op);
        Value emit(Ref<ast::BinaryOp> op);
        Value emit(Ref<ast::UnaryOp> op);
        Value emit(Ref<ast::Branch> branch);
        Value emit(Ref<ast::Ternary> ternary);
        Value emit(Ref<ast::While> loop);
        Value emit(Ref<ast::ForRange> loop);

        void emit(Ref<ast::StructDef> structDef);

        void codegenFunction(Ref<class UserFunction> function, Ref<ast::FunctionDef> funcDef);
        llvm::BasicBlock* codegenBlock(Ref<UserFunction> function,
                                       Ref<ast::Block> block,
                                       llvm::BasicBlock* basicBlock = nullptr,
                                       llvm::BasicBlock* nextBlock = nullptr);
        Ref<Function> resolveFunction(Ref<ast::FunctionCall> call);
    };

} // namespace pepper
