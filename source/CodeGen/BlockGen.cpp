//
// Created by justi on 1/5/2023.
//

#include "AST/Block.h"
#include "Codegen.h"
#include "Frontend/Struct.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::ast;

    llvm::BasicBlock* Codegen::codegenBlock(
        Ref<UserFunction> function, Ref<Block> block, llvm::BasicBlock* basicBlock, llvm::BasicBlock* nextBlock) {
        basicBlock = basicBlock ? basicBlock : function->appendBlock(block->Name);
        ir()->SetInsertPoint(basicBlock);

        // codegen all instructions, and ensure that there's a jump the next block
        Value lastInstr;
        if (block) {
            // track any references that only exist in this scope, they will need cleanup at the end
            Vector<Value> localRefs;
            for (auto& expr : block->Items) {
                lastInstr = codegen(expr);
                // if this was the creation of a struct reference, track it
                if (expr->template is<VariableDef>() && lastInstr.Ty->isStruct())
                    localRefs.emplace_back(lastInstr);
            }
            // clean up any local references
            if (!localRefs.empty()) {
                // if there's already a jump, cleanup needs to be inserted before it
                auto hasJump = lastInstr && llvm::isa<llvm::BranchInst>(*lastInstr);
                if (hasJump)
                    ir()->SetInsertPoint(llvm::cast<llvm::Instruction>(lastInstr.V));
                for (auto& ref : llvm::reverse(localRefs)) {
                    auto type = ref.Ty.template as<StructTypeInfo>();
                    auto release = type->StructDesc->method("__release");
                    release->call({ref});
                }
            }
        }

        // if there is a next block and the end of this block isn't already jumping
        // somewhere, add a jump to the next block
        if (nextBlock && (!lastInstr || !llvm::isa<llvm::BranchInst>(*lastInstr)))
            ir()->CreateBr(nextBlock);

        // There may be nested blocks inside this block, so we return wherever insertion left off
        return ir()->GetInsertBlock();
    }
} // namespace pepper
