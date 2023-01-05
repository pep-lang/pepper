//
// Created by Justin Boswell on 12/29/22.
//
//
// Created by Justin Boswell on 12/28/22.
//

#include "AST/Loops.h"
#include "Codegen.h"
#include "Core/Exceptions.h"
#include "Frontend/Context.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Struct.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"
#include "Value.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<While> loop) {
        auto function = locals()->functionTarget();
        auto& context = function->function()->getContext();
        auto bodyBlock = function->appendBlock("while");
        auto mergeBlock = function->appendBlock("whilecont");

        auto condition = codegen(loop->Condition);
        auto condBool = condition.Ty->ops()->asBool(condition);

        // Initial condition check
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        // generate body, ignoring wherever the insertion point is, we don't care
        codegenBlock(function, loop->Body, bodyBlock);

        // Update condition
        condition = codegen(loop->Condition);
        condBool = condition.Ty->ops()->asBool(condition);
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        // loop is done, set insertion to the continuation block
        ir()->SetInsertPoint(mergeBlock);

        return Value(Types::VoidPtr,
                     llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType())));
    }

    Value Codegen::emit(Ref<ForRange> loop) {
        auto function = locals()->functionTarget();
        auto& context = function->function()->getContext();
        auto bodyBlock = function->appendBlock("for");
        auto mergeBlock = function->appendBlock("forcont");
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
        auto rangeNew = locals()->findFunction("range");
        auto range = rangeNew->call(args);

        auto next = rangeStruct->method("next");
        auto condition = next->call({range});

        // initial condition check
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);

        // generate body, ignoring wherever the insertion point is, we don't care
        codegenBlock(function, loop->Body, bodyBlock);

        // update condition
        condition = next->call({range});
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);

        // loop is done, set insertion to the continuation block
        ir()->SetInsertPoint(mergeBlock);

        return Value(Types::VoidPtr,
                     llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::VoidPtr->llvmType())));
    }

} // namespace pepper
