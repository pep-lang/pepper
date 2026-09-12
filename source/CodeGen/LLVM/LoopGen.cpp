

#include "Address.h"
#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Sema/Model/Loops.h"
#include "Sema/Operations.h"
#include "Sema/SemaContext.h"
#include "Sema/Struct.h"
#include "Sema/Types.h"

namespace pepper {
    Address LLVMCodeGenerator::emit(const sema::While* loop) {
        auto function = locals()->function_target();
        auto& context = function->function()->getContext();
        auto bodyBlock = function->append_block("while");
        auto mergeBlock = function->append_block("whilecont");

        auto condition = codegen(loop->condition);
        auto condBool = condition.type->ops()->asBool(condition);

        // Initial condition check
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        // generate body, ignoring wherever the insertion point is, we don't care
        codegenBlock(function, loop->body, bodyBlock);

        // Update condition
        condition = codegen(loop->condition);
        condBool = condition.type->ops()->asBool(condition);
        ir()->CreateCondBr(condBool, bodyBlock, mergeBlock);

        // loop is done, set insertion to the continuation block
        ir()->SetInsertPoint(mergeBlock);

        return Address(Types::VoidPtr,
                       llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::get(Types::VoidPtr.get()))));
    }

    Address LLVMCodeGenerator::emit(const sema::ForRange* loop) {
        auto function = locals()->function_target();
        auto& context = function->function()->getContext();
        auto bodyBlock = function->append_block("for");
        auto mergeBlock = function->append_block("forcont");
        auto init = codegen(loop->init);
        auto end = maybeCodegen(loop->done);
        auto step = maybeCodegen(loop->step);

        Vector<Address> args;
        args.emplace_back(init);
        if (end)
            args.emplace_back(end);
        if (step)
            args.emplace_back(step);

        auto rangeStruct = Struct::get("range");
        auto rangeNew = locals()->find_function("range");
        auto range = rangeNew->call(args);

        auto next = rangeStruct->method("next");
        auto condition = next->call({range});

        // initial condition check
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);

        // generate body, ignoring wherever the insertion point is, we don't care
        codegenBlock(function, loop->body, bodyBlock);

        // update condition
        condition = next->call({range});
        ir()->CreateCondBr(condition, bodyBlock, mergeBlock);

        // loop is done, set insertion to the continuation block
        ir()->SetInsertPoint(mergeBlock);

        return Address(Types::VoidPtr,
                       llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::get(Types::VoidPtr.get()))));
    }

} // namespace pepper
