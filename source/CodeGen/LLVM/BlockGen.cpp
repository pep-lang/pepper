

#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/LLVMUtils.h"
#include "Sema/Model/Block.h"
#include "Sema/Struct.h"
#include "llvm/IR/BasicBlock.h"

namespace pepper {
    using namespace pepper::sema;

    llvm::BasicBlock* LLVMCodeGenerator::codegenBlock(Ref<UserFunction> function,
                                                      const Block* block,
                                                      llvm::BasicBlock* basicBlock,
                                                      llvm::BasicBlock* nextBlock,
                                                      Vector<Address> localRefs) {
        basicBlock = basicBlock ? basicBlock : function->append_block(block->name);
        ir()->SetInsertPoint(basicBlock);

        // codegen all instructions, and ensure that there's a jump the next block
        Address lastInstr;
        if (block) {
            for (auto& expr : block->items) {
                lastInstr = codegen(expr);
                // if this was the creation of a struct reference, track it
                // Creation of `this` is ignored
                if (expr->is<VariableDef>() && !expr->is<ThisDef>() && !expr->is<FieldDef>()) {
                    auto var = expr->as<VariableDef>();
                    if (lastInstr.type->is<RefType>())
                        localRefs.emplace_back(lastInstr);
                }
            }
            // clean up any local references
            if (!localRefs.empty()) {
                // if there's already a jump, cleanup needs to be inserted before it
                auto hasJump = lastInstr && llvm::isa<llvm::BranchInst>(*lastInstr);
                if (hasJump)
                    ir()->SetInsertPoint(llvm::cast<llvm::Instruction>(lastInstr.value));
                for (auto& ref : llvm::reverse(localRefs)) {
                    auto type = ref.type.template as<RefType>();
                    auto release = type->type()->struct_desc->method("__release");
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
