//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include <string>

#include "Core/Common.h"
#include "llvm/ADT/StringExtras.h"

namespace pepper {
    class Ident : public std::string {
        using super = std::string;

      public:
        Ident()
            : std::string() {}

        Ident(const std::string& str)
            : super(str) {}

        Ident(const char* str)
            : super(str) {}

        Ident(const Ident& name)
            : super(name) {}

        Ident(Ident&& name)
            : super(std::forward<Ident>(name)) {}

        Ident(std::string&& str)
            : super(std::forward<std::string>(str)) {}

        Ident& operator=(const Ident& name) {
            super::assign(name);
            return *this;
        }
    };
} // namespace pepper
