#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ConvertIntrinsics : public Transformer {
        DECLARE_RTTI(ConvertIntrinsics, Transformer);

        ConvertIntrinsics() {}

        struct IntrinsicsConverter : public Visitor {
            void visitType(TypeName& type) override {
                if (type.name == "__ptr") {
                    if (type.sub_types.size() != 1)
                        throw CompileError("__ptr<T> takes only a single generic type argument");
                    auto pointee = type.sub_types.front().to_string();
                    type = {pointee + "*"};
                }
            }

            void visitNode(NodeRef& node) override {
                if (auto func = node->as<FunctionCall>()) {
                    TypeName target = func->target;
                    if (target.name == "__is_pod") {
                        node = new IsPod(func->target);
                    }
                    if (target.name == "__default") {
                        node = new Default(func->target);
                    }
                }
            }
        };

        void run(Ref<Module> module) override {
            auto converter = IntrinsicsConverter();
            for (auto& func : module->functions())
                converter.visit(func);
            for (auto& st : module->structs())
                converter.visit(st);
        }
    };
} // namespace pepper::sema
