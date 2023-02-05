
#pragma once

#include "AST/TypeName.h"
#include "AST/Visitor.h"
#include "llvm/ADT/DenseSet.h"

namespace pepper::ast {
    template <typename T>
    class Resolvable {
        friend class Visitor;

        TypeName Target;
        T* Value = nullptr;

      public:
        Resolvable(const TypeName& name = {})
            : Target(name)
            , Value(nullptr) {
            Instances().insert(this);
        }

        explicit Resolvable(T* value)
            : Value(value)
            , Target(value->Name) {}

        Resolvable(const Resolvable& rhs) {
            Instances().insert(this);
            *this = rhs;
        }

        Resolvable(Resolvable&& rhs) noexcept {
            Instances().insert(this);
            std::swap(*this, rhs);
        }

        ~Resolvable() {
            Instances().erase(this);
        }

        Resolvable& operator=(const Resolvable& rhs) {
            Target = rhs.Target;
            Value = rhs.Value;
            return *this;
        }

        Resolvable& operator=(T* value) {
            Value = value;
            Target = value->Name;
            return *this;
        }

        Resolvable& operator=(const TypeName& name) {
            assert(!Value && "Attempted to overwrite already resolved Resolvable with name");
            Target = name;
            return *this;
        }

        const std::string name() const {
            return (Value) ? Value->Name : Target;
        }

        T* value() const {
            return Value;
        }

        const TypeName& target() const {
            return Target;
        }

        void resolve(T* val) {
            Value = val;
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

        operator T*() const {
            return Value;
        }

        T* operator->() const {
            assert(Value && "Value is not resolved yet");
            return Value;
        }

        void visit(Visitor& visitor) {
            visitor.visit(Target);
        }

        static llvm::DenseSet<Resolvable*>& Instances() {
            static llvm::DenseSet<Resolvable*> instances;
            return instances;
        }
    };

    template <typename T>
    inline void Visitor::visit(Resolvable<T>& target) {
        visit(target.Target);
    }
} // namespace pepper::ast
