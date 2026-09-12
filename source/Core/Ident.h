
#pragma once

#include <string>

#include "Core/Common.h"
#include "llvm/ADT/StringExtras.h"

namespace pepper {
    class Ident : public std::string {
        using super = std::string;

      public:
        constexpr Ident() = default;

        constexpr Ident(const std::string& str)
            : super(str) {}

        constexpr Ident(const char* str)
            : super(str) {}

        constexpr Ident(const Ident& name)
            : super(name) {}

        constexpr Ident(Ident&& name) noexcept
            : super(std::forward<Ident>(name)) {}

        constexpr Ident(std::string&& str)
            : super(std::forward<std::string>(str)) {}

        constexpr Ident(std::string_view sv)
            : super(sv) {}

        Ident& operator=(const Ident& name) {
            super::assign(name);
            return *this;
        }
    };
} // namespace pepper
