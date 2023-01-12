//
// Created by Justin Boswell on 1/5/23.
//

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
            auto dtorItems = st->Destructor->Body->Items;
            st->Destructor->Body->Items.clear();
            for (const auto& release : llvm::reverse(releases)) {
                st->Destructor->Body->Items.emplace_back(release);
            }
            st->Destructor->Body->Items.append(dtorItems);
        }
    };
} // namespace pepper::ast
