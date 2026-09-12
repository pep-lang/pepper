
#pragma once

#include <algorithm>
#include <string>
#include <type_traits>

#include "Core/RTTI.h"
#include "Core/Ref.h"

namespace pepper {

    template <typename T, typename Base>
    concept IsA = std::is_base_of_v<Base, T>;

    template <typename T>
    concept HasToString = requires(T t) {
        { t.to_string() } -> std::same_as<std::string>;
    };

    // Compile-time string, for constexpr
    template <size_t N>
    struct ConstString {
        constexpr ConstString(const char (&str)[N]) {
            std::copy_n(str, N, value);
        }

        constexpr operator std::string_view() const {
            return {value, N - 1};
        }

        char value[N];
    };

    // Scope guard/cleanup
    auto defer(auto&& fn)
        requires std::is_invocable_v<decltype(fn)>
    {
        struct deferred {
            decltype(fn) call;

            ~deferred() {
                call();
            }
        };

        return deferred{std::forward<decltype(fn)>(fn)};
    }
} // namespace pepper

#if defined(_MSC_VER) && !defined(__clang__)
#    define PEP_UNREACHABLE() __assume(false)
#else
#    define PEP_UNREACHABLE() __builtin_unreachable()
#endif

#define PEP_CONCAT(_X, _Y) PEP_CONCAT1(_X, _Y)
#define PEP_CONCAT1(_X, _Y) _X##_Y
