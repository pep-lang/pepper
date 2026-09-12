#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ResolveLiterals : public Transformer {
        DECLARE_RTTI(ResolveLiterals, Transformer);

        struct Resolver : public Visitor {
            SymbolTable symbols;

            Resolver(const SymbolTable& symbols)
                : symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                if (auto neg = node->as<Minus>()) {
                    auto operand = neg->operand;
                    if (auto intLiteral = operand->as<IntegerLiteral>()) {
                        node = new IntegerLiteral(-intLiteral->value);
                        return;
                    }
                    if (auto floatLiteral = operand->as<FloatLiteral>()) {
                        node = new FloatLiteral(-floatLiteral->value);
                        return;
                    }
                }
            }
        };

        void run(Ref<Module> module) override {
            Resolver resolver(*module);

            for (const auto& function : module->functions()) {
                resolver.visit(function);
            }
            for (const auto& st : module->structs()) {
                resolver.visit(st);
            }
        }
    };
} // namespace pepper::sema
