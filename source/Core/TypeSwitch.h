
#pragma once

#include "Core/RTTI.h"
#include "llvm/ADT/Optional.h"

namespace pepper {
    template <HasRtti T>
    struct TypeSwitch {
        const T* Value;
        bool Finished = false;

        TypeSwitch(const T* value)
            : Value(value) {
        }

        template <typename C, typename Callable>
        TypeSwitch& Case(Callable&& call) {
            if (Finished)
                return *this;

            if (Value->template is<C>()) {
                call(Value->template as<C>());
                Finished = true;
            }

            return *this;
        }

        template <typename Callable>
        void Default(Callable&& call) {
            if (Finished)
                return *this;
            call(Value);
        }
    };
} // namespace pepper
