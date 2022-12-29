//
// Created by Justin Boswell on 12/28/22.
//

#include "AST/Branches.h"

#include "Codegen/Context.h"
#include "Codegen/IR/Codegen.h"
#include "Codegen/IR/Value.h"
#include "Codegen/LLVMUtils.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<Branch> branch) {
        auto function = ir()->GetInsertBlock()->getParent();
        auto& context = function->getContext();
        auto thenBlock = llvm::BasicBlock::Create(context, "then", function);
        auto elseBlock = llvm::BasicBlock::Create(context, "else");
        elseBlock->insertInto(function);
        auto mergeBlock = llvm::BasicBlock::Create(context, "ifcont");
        mergeBlock->insertInto(function);
        auto condition = codegen(branch->condition());
        auto condBool = condition.Ty->ops()->asBool(condition);

        // create conditional jump
        ir()->CreateCondBr(condBool, thenBlock, elseBlock);

        // generate then block
        ir()->SetInsertPoint(thenBlock);
        Value thenVal;
        Query(branch->thenBlock()->Items).each([&](auto expr) { thenVal = codegen(expr); });
        ir()->CreateBr(mergeBlock);
        thenBlock = ir()->GetInsertBlock();

        // generate else block
        ir()->SetInsertPoint(elseBlock);
        Value elseVal;
        if (branch->elseBlock()) {
            Query(branch->elseBlock()->Items).each([&](auto expr) { elseVal = codegen(expr); });
        }
        ir()->CreateBr(mergeBlock);
        elseBlock = ir()->GetInsertBlock();

        ir()->SetInsertPoint(mergeBlock);

        // if the values are void or don't match, don't return a phi node
        if (thenVal && elseVal && thenVal->getType() == elseVal->getType()) {
            auto phiNode = ir()->CreatePHI(thenVal->getType(), 2, "iftmp");
            phiNode->addIncoming(thenVal, thenBlock);
            phiNode->addIncoming(elseVal, elseBlock);
            return Value(thenVal.Ty, phiNode);
        }
        return Value(Types::VoidPtr,
                     llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType())));
    }
} // namespace pepper
