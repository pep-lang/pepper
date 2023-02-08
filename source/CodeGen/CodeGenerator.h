
#pragma once

#include <memory>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Address.h"
#include "CodeGenModule.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Sema/Scope.h"
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
        Address maybeCodegen(ast::Node* node) {
            return node ? codegen(node) : Address::Null();
        }

        static Ref<Scope> locals();
        static Ref<Scope> globals();
        void pushFunction(Ref<UserFunction> function);
        void pushScope(const Ident& name);
        void popScope();

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        Address codegen(const ast::Node* node);

        // individual AST -> IR transforms
        Address emit(const ast::SymbolRef* symbol);
        Address emit(const ast::VariableDef* variableDef);
        Address emit(const ast::ThisDef* thisDef);
        Address emit(const ast::PointerLiteral* pointerLiteral);
        Address emit(const ast::StringLiteral* stringLiteral);
        Address emit(const ast::IntegerLiteral* intLiteral);
        Address emit(const ast::FloatLiteral* floatLiteral);
        Address emit(const ast::BoolLiteral* boolLiteral);
        Address emit(const ast::FieldDef* fieldDef);
        Address emit(const ast::MemberRef* memberRef);
        Address emit(const ast::ThisRef* thisRef);
        Address emit(const ast::ExternFunctionRef* externFuncDef);
        Address emit(const ast::FunctionDef* functionDef);
        Address emit(const ast::Return* ret);
        Address emit(const ast::FunctionCall* call);
        Address emit(const ast::MethodCall* call);
        Address emit(const ast::Assign* op);
        Address emit(const ast::CompoundAssign* op);
        Address emit(const ast::BinaryOp* op);
        Address emit(const ast::UnaryOp* op);
        Address emit(const ast::Branch* branch);
        Address emit(const ast::Ternary* ternary);
        Address emit(const ast::While* loop);
        Address emit(const ast::ForRange* loop);
        Address emit(const ast::Intrinsic* intrinsic);
        Address emit(const ast::Index* index);

        void instantiate(const ast::StructDef* structDef);
        void instantiateMethods(const ast::StructDef* structDef);
        void instantiate(const ast::FunctionNode* fn);

        void codegenStruct(const ast::StructDef* structDef);
        void codegenFunction(Ref<class UserFunction> function, const ast::FunctionDef* funcDef);
        llvm::BasicBlock* codegenBlock(Ref<UserFunction> function,
                                       const ast::Block* block,
                                       llvm::BasicBlock* basicBlock = nullptr,
                                       llvm::BasicBlock* nextBlock = nullptr,
                                       Vector<Address> localRefs = {});
        Address emitSizeOf(const ast::SizeOf* sizeOf);
        Address emitArrayIndex(const ast::ArrayIndex* index);
        Address emitIsPod(const ast::IsPod* isPod);
        Address emitDefault(const ast::Default* defaultVal);
        Ref<Function> resolveFunction(const ast::FunctionCall* call);
    };

} // namespace pepper
