

#pragma once

#include "AST/Nodes.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ReleaseFieldRefs : public Transformer {
        DECLARE_RTTI(ReleaseFieldRefs, Transformer);

        SymbolTable Symbols;

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);
            for (const auto& st : parseTree->structs()) {
                visitStruct(st);
            }
        }

        void visitStruct(StructDef* st) {
            Vector<Node*> releases;
            for (const auto& field : st->Fields) {
                if (auto fieldType = Symbols.Structs.lookup(field->Type.toString())) {
                    // Set the release source location to be the location of the final dtor instruction
                    Node::PushSource(st->Destructor->Body->Items.back()->Source);
                    releases.emplace_back(new MethodCall(new MemberRef(new ThisRef(), field->Name), {"__release"}));
                    Node::PopSource();
                }
            }
            // Insert the releases in reverse declaration order just before the last dtor instruction (free)
            auto& dtorItems = st->Destructor->Body->Items;
            for (auto& release : llvm::reverse(releases)) {
                auto beforeFree = std::prev(dtorItems.end());
                dtorItems.insert(beforeFree, release);
            }
        }
    };
} // namespace pepper::ast
