

#pragma once

#include "AST/Nodes.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ReleaseFieldRefs : public Transformer {
        llvm::StringMap<Ref<StructDef>> Structs;

        void run(Ref<AST> parseTree) override {
            for (auto root : parseTree->roots()) {
                if (root->is<StructDef>()) {
                    auto st = root.as<StructDef>();
                    Structs[st->Type.toString()] = st;
                }
            }
            for (const auto& st : Structs) {
                visitStruct(st.getValue());
            }
        }

        void visitStruct(Ref<StructDef> st) {
            Vector<Ref<Node>> releases;
            for (const auto& field : st->Fields) {
                if (auto fieldType = Structs.lookup(field->Type.toString())) {
                    releases.emplace_back(Ref<MethodCall>::New(
                        fieldType->Type, Ref<MemberRef>::New(Ref<ThisRef>::New(), field->Name), "__release"));
                }
            }
            // Insert the releases in reverse declaration order just before the last dtor instruction (free)
            auto& dtorItems = st->Destructor->Body->Items;
            for (const auto& release : llvm::reverse(releases)) {
                dtorItems.insert(dtorItems.end() - 1, release);
            }
        }
    };
} // namespace pepper::ast
