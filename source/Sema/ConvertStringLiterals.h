
#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Sema/Transform.h"

namespace pepper::sema {
    struct ConvertStringLiterals : public Transformer {
        DECLARE_RTTI(ConvertStringLiterals, Transformer);

        struct StringConverter : public Visitor {
            void visitNode(NodeRef& node) {
                if (auto str = node->as<StringLiteral>()) {
                    if (str->is_raw)
                        return;
                    Node::push_source(node->source_loc);
                    node = new FunctionCall({"string"}, {str, new IntegerLiteral(str->value.length())});
                    Node::pop_source();
                }
            }
        };

        void run(Ref<Module> module) override {
            StringConverter converter;

            for (auto& st : module->structs()) {
                converter.visit(st);
            }

            for (auto& fn : module->functions()) {
                converter.visit(fn);
            }
        }
    };
} // namespace pepper::sema
