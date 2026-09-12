
#pragma once

#include <cstdint>

#include "Sema/Model/Node.h"

namespace pepper::sema {
    struct Literal : public Expression {
        DECLARE_RTTI(Literal, Expression);
    };

    struct BoolLiteral : public Literal {
        DECLARE_RTTI(BoolLiteral, Literal);
        SEMA_NODE_POD_CLONE(BoolLiteral);

        const bool value;

        explicit BoolLiteral(bool value)
            : value(value) {}

        const TypeName& type() const override {
            static TypeName Bool("bool");
            return Bool;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}: {1}", node_name(), value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0}({1})", Node::dump(indent), std::to_string(value));
        }
    };

    struct IntegerLiteral : public Literal {
        DECLARE_RTTI(IntegerLiteral, Literal);
        SEMA_NODE_POD_CLONE(IntegerLiteral);

        const int64_t value;

        explicit IntegerLiteral(int64_t value)
            : value(value) {}

        [[nodiscard]] const TypeName& type() const override {
            static TypeName Long("long");
            return Long;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}({1})", node_name(), value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), std::to_string(value));
        }
    };

    struct FloatLiteral : public Literal {
        DECLARE_RTTI(FloatLiteral, Literal);
        SEMA_NODE_POD_CLONE(FloatLiteral);

        const double value;

        FloatLiteral(double value)
            : value(value) {}

        const TypeName& type() const override {
            static TypeName Double("double");
            return Double;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}({1})", node_name(), value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), std::to_string(value));
        }
    };

    struct StringLiteral : public Literal {
        DECLARE_RTTI(StringLiteral, Literal);
        SEMA_NODE_POD_CLONE(StringLiteral);

        const std::string value;
        bool is_raw;

        StringLiteral(const std::string& value, bool raw = false)
            : value(value)
            , is_raw(raw) {}

        const TypeName& type() const override {
            static TypeName String("string");
            return String;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}({1}\"{2}\")", node_name(), is_raw ? "@" : "", value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), value);
        }
    };

    struct PointerLiteral : public Literal {
        DECLARE_RTTI(PointerLiteral, Literal);
        SEMA_NODE_POD_CLONE(PointerLiteral);

        const uint64_t value;

        explicit PointerLiteral(uint64_t value = 0)
            : value(value) {}

        [[nodiscard]] const TypeName& type() const override {
            static TypeName Ptr("ptr");
            return Ptr;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}({1})", node_name(), value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), value);
        }

        static PointerLiteral* null() {
            static PointerLiteral* nullRef = new PointerLiteral(0);
            return nullRef;
        }
    };
} // namespace pepper::sema
