//
// Created by justi on 1/5/2023.
//

#include "AST/Block.h"
#include "Codegen/IR/Codegen.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::ast;

    llvm::BasicBlock* Codegen::codegenBlock(
        Ref<UserFunction> function, Ref<Block> block, llvm::BasicBlock* basicBlock, llvm::BasicBlock* nextBlock) {
        basicBlock = basicBlock ? basicBlock : function->appendBlock(block->Name);
        ir()->SetInsertPoint(basicBlock);

        // codegen all instructions, and ensure that there's a jump the next block
        if (block) {
            Value lastVal;
            Query(block->Items).each([&](auto expr) { lastVal = codegen(expr); });
            if (nextBlock && (!lastVal || !llvm::isa<llvm::BranchInst>(*lastVal)))
                ir()->CreateBr(nextBlock);
        }

        // There may be nested blocks inside this block, so we return wherever insertion left off
        return ir()->GetInsertBlock();
    }
} // namespace pepper
