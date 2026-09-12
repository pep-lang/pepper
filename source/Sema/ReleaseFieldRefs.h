

#pragma once

#include "Sema/Model/Nodes.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ReleaseFieldRefs : public Transformer {
        DECLARE_RTTI(ReleaseFieldRefs, Transformer);

        SymbolTable symbols;

        void run(Ref<Module> module) override {
            symbols = SymbolTable(*module);
            for (const auto& st : module->structs()) {
                visitStruct(st);
            }
        }

        void visitStruct(StructDef* st) {
            Vector<Node*> releases;
            for (const auto& field : st->field_members) {
                if (auto fieldType = symbols.structs.lookup(field->type.to_string())) {
                    // Set the release source location to be the location of the final dtor instruction
                    Node::push_source(st->destruct->body->items.back()->source_loc);
                    releases.emplace_back(new MethodCall(new MemberRef(new ThisRef(), field->name), {"__release"}));
                    Node::pop_source();
                }
            }
            // Insert the releases in reverse declaration order just before the last dtor instruction (free)
            auto& dtorItems = st->destruct->body->items;
            for (auto& release : llvm::reverse(releases)) {
                auto beforeFree = std::prev(dtorItems.end());
                dtorItems.insert(beforeFree, release);
            }
        }
    };
} // namespace pepper::sema
