
#pragma once

#include "Sema/Model/TypeName.h"
#include "Sema/Model/Visitor.h"
#include "llvm/ADT/DenseSet.h"

namespace pepper::sema {
    class ResolvableBase {
        friend class Visitor;

        TypeName target_id;
        const RTTI* target_type;
        Node* target_node;

      public:
        ResolvableBase(const RTTI* type = nullptr, const TypeName& name = {})
            : target_id(name)
            , target_type(type)
            , target_node(nullptr) {}

        ResolvableBase(const ResolvableBase&) = default;
        ResolvableBase(ResolvableBase&&) = default;
        ResolvableBase& operator=(const ResolvableBase& rhs) = default;

        ResolvableBase& operator=(Node* value) {
            assert(value->rtti()->is(target_type) && "Assigned value type does not match expected type");
            target_node = value;
            return *this;
        }

        ResolvableBase& operator=(const TypeName& name) {
            assert(!target_node && "Attempted to overwrite already resolved Resolvable with name");
            target_id = name;
            return *this;
        }

        Node* value() const {
            return target_node;
        }

        template <typename N>
        N* valueAs() const {
            if (auto val = value())
                return val->as<N>();
            return nullptr;
        }

        void resolve(Node* value) {
            assert(value->rtti()->is(target_type) && "Resolved value type does not match expected type");
            target_node = value;
        }

        const RTTI* type() const {
            return target_type;
        }

        const std::string name() const {
            return target_id;
        }

        const TypeName& target() const {
            return target_id;
        }

        const std::string to_string() const {
            return target_id.to_string();
        }

        operator bool() const {
            return !target_id.empty() || !!target_node;
        }

        operator TypeName() const {
            return target_id;
        };

        void visit(Visitor& visitor) {
            visitor.visit(target_id);
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
        visit(target.target_id);
        visitResolvable(target);
    }

    struct Resolver : public Visitor {
        virtual void visitResolvable(ResolvableBase& target) = 0;
    };
} // namespace pepper::sema
