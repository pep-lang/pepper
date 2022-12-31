//
// Created by Justin Boswell on 12/29/22.
//
//
// Created by Justin Boswell on 12/28/22.
//

#include "AST/Loops.h"

#include "Codegen/Context.h"
#include "Codegen/IR/Codegen.h"
#include "Codegen/IR/Value.h"
#include "Codegen/LLVMUtils.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<While> loop) {
        auto function = ir()->GetInsertBlock()->getParent();
        auto& context = function->getContext();
        auto bodyBlock = llvm::BasicBlock::Create(context, "while", function);
        auto mergeBlock = llvm::BasicBlock::Create(context, "whilecont");
        mergeBlock->insertInto(function);

        auto condition = codegen(loop->Condition);
        auto condBool = condition.Ty->ops()->asBool(condition);

        // Initial condition check
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        ir()->SetInsertPoint(bodyBlock);

        // emit body
        Query(loop->Body->Items).each([this](auto& expr) { codegen(expr); });

        // Update condition
        condition = codegen(loop->Condition);
        condBool = condition.Ty->ops()->asBool(condition);
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        ir()->SetInsertPoint(mergeBlock);

        return Value(Types::VoidPtr,
                     llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType())));
    }

    Value Codegen::emit(Ref<ForRange> loop) {
        auto function = ir()->GetInsertBlock()->getParent();
        auto& context = function->getContext();
        auto bodyBlock = llvm::BasicBlock::Create(context, "for", function);
        auto mergeBlock = llvm::BasicBlock::Create(context, "forcont");
        mergeBlock->insertInto(function);
        auto init = codegen(loop->Init);

        // TODO: insert range here

        return Value();
    }

} // namespace pepper
