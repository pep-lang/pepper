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
#include "Codegen/Struct.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<While> loop) {
        auto function = Context::get().locals()->functionTarget();
        auto& context = function->function()->getContext();
        auto bodyBlock = llvm::BasicBlock::Create(context, "while", function->function(), function->Return);
        auto mergeBlock = llvm::BasicBlock::Create(context, "whilecont", function->function(), function->Return);

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
        auto end = maybeCodegen(loop->Done);
        auto step = maybeCodegen(loop->Step);

        Vector<Value> args;
        args.emplace_back(init);
        if (end)
            args.emplace_back(end);
        if (step)
            args.emplace_back(step);

        auto rangeStruct = Struct::get("range");
        auto rangeNew = Context::get().locals()->findFunction("range");
        auto range = rangeNew->call(args);

        auto next = rangeStruct->method("next");
        auto condition = next->call({range});

        // initial condition check
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);
        ir()->SetInsertPoint(bodyBlock);
        // body
        Query(loop->Body->Items).each([this](auto& expr) { codegen(expr); });
        // update condition
        condition = next->call({range});
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);

        ir()->SetInsertPoint(mergeBlock);

        return Value(Types::VoidPtr,
                     llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType())));
    }

} // namespace pepper
