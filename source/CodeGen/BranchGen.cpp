//
// Created by Justin Boswell on 12/28/22.
//

#include "AST/Branches.h"
#include "Address.h"
#include "CodeGenerator.h"
#include "Core/Exceptions.h"
#include "Frontend/Context.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Operations.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

    Address CodeGenerator::emit(Ref<Branch> branch) {
        auto function = locals()->functionTarget();
        auto& context = function->function()->getContext();
        auto thenBlock = function->appendBlock("then");
        auto elseBlock = branch->Else ? function->appendBlock("else") : nullptr;
        auto mergeBlock = function->appendBlock("ifcont");

        // create conditional jump
        auto condition = codegen(branch->Condition);
        auto condBool = condition.Ty->ops()->asBool(condition);
        ir()->CreateCondBr(condBool, thenBlock, elseBlock ? elseBlock : mergeBlock);

        // generate then block
        thenBlock = codegenBlock(function, branch->Then, thenBlock, mergeBlock);

        // generate else block if needed
        if (elseBlock) {
            elseBlock = codegenBlock(function, branch->Else, elseBlock, mergeBlock);
        }

        // set the builder to the head of the merge block for whatever is next
        ir()->SetInsertPoint(mergeBlock);

        return Address{Types::VoidPtr,
                       llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType()))};
    }

    Address CodeGenerator::emit(Ref<Ternary> ternary) {
        auto function = locals()->functionTarget();
        auto& context = function->function()->getContext();
        auto trueBlock = function->appendBlock("true");
        auto falseBlock = function->appendBlock("false");
        auto mergeBlock = function->appendBlock("ternarycont");
        auto condition = codegen(ternary->Condition);
        auto condBool = condition.Ty->ops()->asBool(condition);

        // create conditional jump
        ir()->CreateCondBr(condBool, trueBlock, falseBlock);

        ir()->SetInsertPoint(trueBlock);
        Address trueValue = codegen(ternary->TrueResult);
        ir()->CreateBr(mergeBlock);
        trueBlock = ir()->GetInsertBlock();

        ir()->SetInsertPoint(falseBlock);
        Address falseValue = codegen(ternary->FalseResult);
        ir()->CreateBr(mergeBlock);
        falseBlock = ir()->GetInsertBlock();

        ir()->SetInsertPoint(mergeBlock);
        auto phi = ir()->CreatePHI(trueValue->getType(), 2, "ternary");
        phi->addIncoming(trueValue, trueBlock);
        phi->addIncoming(falseValue, falseBlock);
        return Address{trueValue.Ty, phi};
    }
} // namespace pepper
