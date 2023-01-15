
#pragma once

#include <memory>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Address.h"
#include "CodeGenModule.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Frontend/Scope.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    class CodeGenerator {
      protected:
        Ref<CodeGenModule> Module;

      public:
        CodeGenerator(Ref<CodeGenModule> module);

        // entry point to codegen, runs all the roots of the AST and generates them
        void generate(Ref<ast::AST> parseTree);

      protected:
        template <typename N>
        Address maybeCodegen(Ref<N> node) {
            return node ? codegen(node) : Address::Null();
        }

        static Ref<Scope> locals();
        static Ref<Scope> globals();
        void pushFunction(Ref<UserFunction> function);
        void pushScope(const Ident& name);
        void popScope();

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        Address codegen(Ref<ast::Node> node);

        // individual AST -> IR transforms
        Address emit(Ref<ast::SymbolRef> variableRef);
        Address emit(Ref<ast::VariableDef> variableDef);
        Address emit(Ref<ast::ThisDef> thisDef);
        Address emit(Ref<ast::PointerLiteral> pointerLiteral);
        Address emit(Ref<ast::StringLiteral> stringLiteral);
        Address emit(Ref<ast::IntegerLiteral> intLiteral);
        Address emit(Ref<ast::FloatLiteral> floatLiteral);
        Address emit(Ref<ast::BoolLiteral> boolLiteral);
        Address emit(Ref<ast::FieldDef> fieldDef);
        Address emit(Ref<ast::MemberRef> memberRef);
        Address emit(Ref<ast::ThisRef> thisRef);
        Address emit(Ref<ast::ExternFunctionDef> externFuncDef);
        Address emit(Ref<ast::FunctionDef> functionDef);
        Address emit(Ref<ast::Return> ret);
        Address emit(Ref<ast::FunctionCall> call);
        Address emit(Ref<ast::MethodCall> call);
        Address emit(Ref<ast::Assign> op);
        Address emit(Ref<ast::CompoundAssign> op);
        Address emit(Ref<ast::BinaryOp> op);
        Address emit(Ref<ast::UnaryOp> op);
        Address emit(Ref<ast::Branch> branch);
        Address emit(Ref<ast::Ternary> ternary);
        Address emit(Ref<ast::While> loop);
        Address emit(Ref<ast::ForRange> loop);
        Address emit(Ref<ast::SizeOf> sizeOf);

        void instantiate(Ref<ast::StructDef> structDef);
        void instantiate(Ref<ast::FunctionDef> functionDef);

        void codegenStruct(Ref<ast::StructDef> structDef);

        void codegenFunction(Ref<class UserFunction> function, Ref<ast::FunctionDef> funcDef);
        llvm::BasicBlock* codegenBlock(Ref<UserFunction> function,
                                       Ref<ast::Block> block,
                                       llvm::BasicBlock* basicBlock = nullptr,
                                       llvm::BasicBlock* nextBlock = nullptr);
        Ref<Function> resolveFunction(Ref<ast::FunctionCall> call);
    };

} // namespace pepper
