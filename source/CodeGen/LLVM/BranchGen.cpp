

#include "CodeGen/LLVM/Address.h"
#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Sema/Model/Branches.h"
#include "Sema/Operations.h"
#include "Sema/SemaContext.h"
#include "Sema/Types.h"

namespace pepper {
    using namespace pepper::sema;

    Address LLVMCodeGenerator::emit(const Branch* branch) {
        auto function = locals()->function_target();
        auto& context = function->function()->getContext();
        auto thenBlock = function->append_block("then");
        auto elseBlock = branch->else_block ? function->append_block("else") : nullptr;
        auto mergeBlock = function->append_block("ifcont");

        // create conditional jump
        auto condition = codegen(branch->condition);
        auto condBool = condition.type->ops()->asBool(condition);
        ir()->CreateCondBr(condBool, thenBlock, elseBlock ? elseBlock : mergeBlock);

        // generate then block
        thenBlock = codegenBlock(function, branch->then_block, thenBlock, mergeBlock);

        // generate else block if needed
        if (elseBlock) {
            elseBlock = codegenBlock(function, branch->else_block, elseBlock, mergeBlock);
        }

        // set the builder to the head of the merge block for whatever is next
        ir()->SetInsertPoint(mergeBlock);

        return Address{Types::VoidPtr,
                       llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(Types::get(Types::VoidPtr.get())))};
    }

    Address LLVMCodeGenerator::emit(const Ternary* ternary) {
        auto function = locals()->function_target();
        auto& context = function->function()->getContext();
        auto trueBlock = function->append_block("true");
        auto falseBlock = function->append_block("false");
        auto mergeBlock = function->append_block("ternarycont");
        auto condition = codegen(ternary->condition);
        auto condBool = condition.type->ops()->asBool(condition);

        // create conditional jump
        ir()->CreateCondBr(condBool, trueBlock, falseBlock);

        ir()->SetInsertPoint(trueBlock);
        Address trueValue = codegen(ternary->true_expr);
        ir()->CreateBr(mergeBlock);
        trueBlock = ir()->GetInsertBlock();

        ir()->SetInsertPoint(falseBlock);
        Address falseValue = codegen(ternary->false_expr);
        ir()->CreateBr(mergeBlock);
        falseBlock = ir()->GetInsertBlock();

        ir()->SetInsertPoint(mergeBlock);
        auto phi = ir()->CreatePHI(trueValue->getType(), 2, "ternary");
        phi->addIncoming(trueValue, trueBlock);
        phi->addIncoming(falseValue, falseBlock);
        return Address{trueValue.type, phi};
    }
} // namespace pepper
