
#pragma once

#include "AST/TypeName.h"
#include "AST/Visitor.h"
#include "llvm/ADT/DenseSet.h"

namespace pepper::ast {
    class ResolvableBase {
        friend class Visitor;

        TypeName Target;
        const RTTI* Type;
        Node* Value;

      public:
        ResolvableBase(const RTTI* type = nullptr, const TypeName& name = {})
            : Target(name)
            , Type(type)
            , Value(nullptr) {}

        ResolvableBase(const ResolvableBase&) = default;
        ResolvableBase(ResolvableBase&&) = default;
        ResolvableBase& operator=(const ResolvableBase& rhs) = default;

        ResolvableBase& operator=(Node* value) {
            assert(value->rtti()->is(Type) && "Assigned value type does not match expected type");
            Value = value;
            return *this;
        }

        ResolvableBase& operator=(const TypeName& name) {
            assert(!Value && "Attempted to overwrite already resolved Resolvable with name");
            Target = name;
            return *this;
        }

        Node* value() const {
            return Value;
        }

        template <typename N>
        N* valueAs() const {
            if (auto val = value())
                return val->as<N>();
            return nullptr;
        }

        void resolve(Node* value) {
            assert(value->rtti()->is(Type) && "Resolved value type does not match expected type");
            Value = value;
        }

        const RTTI* type() const {
            return Type;
        }

        const std::string name() const {
            return Target;
        }

        const TypeName& target() const {
            return Target;
        }

        const std::string toString() const {
            return Target.toString();
        }

        operator bool() const {
            return !Target.empty() || !!Value;
        }

        operator TypeName() const {
            return Target;
        };

        void visit(Visitor& visitor) {
            visitor.visit(Target);
        }
    };

    template <typename T>
    class Resolvable : public ResolvableBase {
        friend class Visitor;

        using Base = ResolvableBase;

      public:
        Resolvable(const TypeName& name = {})
            : ResolvableBase(RTTI::of<T>(), name) {}

        explicit Resolvable(T* value)
            : ResolvableBase(RTTI::of<T>(), value->Name) {
            resolve(value);
        }

        T* value() const {
            return Base::valueAs<T>();
        }

        Resolvable& operator=(T* value) {
            Base::operator=(static_cast<Node*>(value));
            return *this;
        }

        operator T*() const {
            assert(value() && "Value is not resolved yet");
            return value();
        }

        T* operator->() const {
            assert(value() && "Value is not resolved yet");
            return value();
        }
    };

    template <typename T>
    inline void Visitor::visit(Resolvable<T>& target) {
        visit(target.Target);
        visitResolvable(target);
    }

    struct Resolver : public Visitor {
        virtual void visitResolvable(ResolvableBase& target) = 0;
    };
} // namespace pepper::ast
