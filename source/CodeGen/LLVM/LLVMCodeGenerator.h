
#pragma once

#include <memory>

#include "CodeGen/CodeGenerator.h"
#include "CodeGen/LLVM/Address.h"
#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Sema/Model/Module.h"
#include "Sema/Model/Nodes.h"
#include "Sema/Scope.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    class LLVMCodeGenerator : public ICodeGenerator {
      protected:
        Ref<LLVMModuleGenerator> module;
        std::string object_file_path;

      public:
        LLVMCodeGenerator(Ref<LLVMModuleGenerator> module_gen);

        // entry point to codegen, runs all the roots of the AST and generates them
        void generate(Ref<sema::Module> parseTree, Ref<Options> options) override;

        std::string get_object_file_path() const override;

      protected:
        Address maybeCodegen(sema::Node* node) {
            return node ? codegen(node) : Address::null();
        }

        static Ref<Scope> locals();
        static Ref<Scope> globals();
        void push_function(Ref<UserFunction> function);
        void push_scope(const Ident& name);
        void pop_scope();

        // Entry to polymorphic emit calls, use this to force generation of a node and its children
        Address codegen(const sema::Node* node);

        // individual AST -> IR transforms
        Address emit(const sema::SymbolRef* symbol);
        Address emit(const sema::VariableDef* variableDef);
        Address emit(const sema::ThisDef* thisDef);
        Address emit(const sema::PointerLiteral* pointerLiteral);
        Address emit(const sema::StringLiteral* stringLiteral);
        Address emit(const sema::IntegerLiteral* intLiteral);
        Address emit(const sema::FloatLiteral* floatLiteral);
        Address emit(const sema::BoolLiteral* boolLiteral);
        Address emit(const sema::FieldDef* fieldDef);
        Address emit(const sema::MemberRef* memberRef);
        Address emit(const sema::ThisRef* thisRef);
        Address emit(const sema::ExternFunctionRef* externFuncDef);
        Address emit(const sema::FunctionDef* functionDef);
        Address emit(const sema::Return* ret);
        Address emit(const sema::FunctionCall* call);
        Address emit(const sema::MethodCall* call);
        Address emit(const sema::Assign* op);
        Address emit(const sema::CompoundAssign* op);
        Address emit(const sema::BinaryOp* op);
        Address emit(const sema::UnaryOp* op);
        Address emit(const sema::Branch* branch);
        Address emit(const sema::Ternary* ternary);
        Address emit(const sema::While* loop);
        Address emit(const sema::ForRange* loop);
        Address emit(const sema::Intrinsic* intrinsic);
        Address emit(const sema::Index* index);

        void instantiate(const sema::StructDef* structDef);
        void instantiateMethods(const sema::StructDef* structDef);
        void instantiate(const sema::FunctionNode* fn);

        void codegenStruct(const sema::StructDef* structDef);
        void codegenFunction(Ref<class UserFunction> function, const sema::FunctionDef* funcDef);
        llvm::BasicBlock* codegenBlock(Ref<UserFunction> function,
                                       const sema::Block* block,
                                       llvm::BasicBlock* basicBlock = nullptr,
                                       llvm::BasicBlock* nextBlock = nullptr,
                                       Vector<Address> localRefs = {});
        Address emitSizeOf(const sema::SizeOf* sizeOf);
        Address emitArrayIndex(const sema::ArrayIndex* index);
        Address emitIsPod(const sema::IsPod* isPod);
        Address emitDefault(const sema::Default* defaultVal);
        Ref<Function> resolveFunction(const sema::FunctionCall* call);
    };

} // namespace pepper
