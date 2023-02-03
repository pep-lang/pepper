#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ConvertIntrinsics : public Transformer {
        DECLARE_RTTI(ConvertIntrinsics, Transformer);

        ConvertIntrinsics() {}

        struct IntrinsicsConverter : public Visitor {
            void visitType(TypeName& type) override {
                if (type.Name == "__ptr") {
                    if (type.SubTypes.size() != 1)
                        throw CompileError("__ptr<T> takes only a single generic type argument");
                    auto pointee = type.SubTypes.front().toString();
                    type = {pointee + "*"};
                }
            }

            void visitNode(NodeRef& node) override {
                if (auto func = node->as<FunctionCall>()) {
                    TypeName target = func->Target;
                    if (target.Name == "__is_pod") {
                        node = new IsPod(func->Target);
                    }
                    if (target.Name == "__default") {
                        node = new Default(func->Target);
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            auto converter = IntrinsicsConverter();
            for (auto& func : parseTree->functions())
                converter.visit(func);
            for (auto& st : parseTree->structs())
                converter.visit(st);
        }
    };
} // namespace pepper::ast
