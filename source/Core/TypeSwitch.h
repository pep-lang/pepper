
#pragma once

#include "Core/RTTI.h"
#include <optional>

namespace pepper {
    // Version of llvm's TypeSwitch that uses pepper's RTTI

    namespace detail {
        template <typename TS, HasRtti T>
        class TypeSwitchBase {
          protected:
            T Value;

          public:
            TypeSwitchBase(const T& value)
                : Value(value) {}

            TypeSwitchBase(TypeSwitchBase&& ts)
                : Value(ts.Value) {}

            ~TypeSwitchBase() = default;

            TypeSwitchBase(const TypeSwitchBase&) = delete;
            void operator=(const TypeSwitchBase&) = delete;
            void operator=(TypeSwitchBase&&) = delete;

            template <typename TCase, typename TCase2, typename... TCases, typename TCallable>
            LLVM_ATTRIBUTE_ALWAYS_INLINE TS& Case(TCallable&& caseFn) {
                TS& ts = static_cast<TS&>(*this);
                return ts.template Case<TCase>(caseFn).template Case<TCase2, TCases...>(caseFn);
            }

            template <typename TCallable>
            TS& Case(TCallable&& caseFn) {
                using Traits = llvm::function_traits<std::decay_t<TCallable>>;
                using TCase = std::remove_cv_t<
                    std::remove_pointer_t<std::remove_reference_t<typename Traits::template arg_t<0>>>>;
                TS& derived = static_cast<TS&>(*this);
                return derived.template Case<TCase>(std::forward<TCallable>(caseFn));
            }
        };
    } // namespace detail

    template <HasRtti T, typename TResult = void>
    class TypeSwitch : public detail::TypeSwitchBase<TypeSwitch<T, TResult>, T> {
        std::optional<TResult> Result;

      public:
        using Base = detail::TypeSwitchBase<TypeSwitch<T, TResult>, T>;
        using Base::Base;
        using Base::Case;
        TypeSwitch(TypeSwitch&&) = default;

        template <typename TCase, typename TCallable>
        TypeSwitch& Case(TCallable&& caseFn) {
            if (Result)
                return *this;

            if (auto val = this->Value->template as<TCase>()) {
                Result = caseFn(val);
            }

            return *this;
        }

        template <typename TCallable>
        TResult Default(TCallable&& defaultFn) {
            if (Result)
                return *this;
            return defaultFn(this->Value);
        }

        TResult Default(TResult defaultResult) {
            if (Result)
                return std::move(*Result);
            return defaultResult;
        }

        operator TResult() {
            assert(Result && "Fallthrough on the end of a type switch");
            return std::move(*Result);
        }
    };

    template <HasRtti T>
    class TypeSwitch<T, void> : public detail::TypeSwitchBase<TypeSwitch<T, void>, T> {
        bool Finished = false;

      public:
        using Base = detail::TypeSwitchBase<TypeSwitch<T, void>, T>;
        using Base::Base;
        using Base::Case;
        TypeSwitch(TypeSwitch&&) = default;

        template <typename TCase, typename TCallable>
        TypeSwitch<T, void>& Case(TCallable&& caseFn) {
            if (Finished)
                return *this;
            if (auto val = this->Value->template as<TCase>()) {
                caseFn(val);
                Finished = true;
            }
            return *this;
        }

        template <typename TCallable>
        void Default(TCallable&& defaultFn) {
            if (!Finished)
                defaultFn(this->Value);
        }
    };
} // namespace pepper
