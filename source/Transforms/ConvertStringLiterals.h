
#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Transforms/Transform.h"

namespace pepper::ast {
    struct ConvertStringLiterals : public Transformer {
        DECLARE_RTTI(ConvertStringLiterals, Transformer);

        struct StringConverter : public Visitor {
            void visitNode(NodeRef& node) {
                if (auto str = node->as<StringLiteral>()) {
                    if (str->Raw)
                        return;
                    node = new FunctionCall({"string"}, {str, new IntegerLiteral(str->Value.length())});
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            StringConverter converter;

            for (auto& st : parseTree->structs()) {
                converter.visit(st);
            }

            for (auto& fn : parseTree->functions()) {
                converter.visit(fn);
            }
        }
    };
} // namespace pepper::ast
