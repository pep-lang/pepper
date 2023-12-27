#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveLiterals : public Transformer {
        DECLARE_RTTI(ResolveLiterals, Transformer);

        struct Resolver : public Visitor {
            SymbolTable Symbols;

            Resolver(const SymbolTable& symbols)
                : Symbols(symbols) {}

            void visitNode(NodeRef& node) override {
                if (auto neg = node->as<Minus>()) {
                    auto operand = neg->Operand;
                    if (auto intLiteral = operand->as<IntegerLiteral>()) {
                        node = new IntegerLiteral(-intLiteral->Value);
                        return;
                    }
                    if (auto floatLiteral = operand->as<FloatLiteral>()) {
                        node = new FloatLiteral(-floatLiteral->Value);
                        return;
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            Resolver resolver(*parseTree);

            for (const auto& function : parseTree->functions()) {
                resolver.visit(function);
            }
            for (const auto& st : parseTree->structs()) {
                resolver.visit(st);
            }
        }
    };
} // namespace pepper::ast
