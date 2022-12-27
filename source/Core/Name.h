//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include <string>

#include "Core/Common.h"
#include "llvm/ADT/StringExtras.h"

namespace pepper {
    class Name : public std::string {
        using super = std::string;

      public:
        Name()
            : std::string() {
        }

        Name(const std::string& str)
            : super(str) {
        }

        Name(const char* str)
            : super(str) {
        }

        Name(const Name& name)
            : super(name) {
        }

        Name(Name&& name)
            : super(std::forward<Name>(name)) {
        }

        Name(std::string&& str)
            : super(std::forward<std::string>(str)) {
        }

        Name& operator=(const Name& name) {
            super::assign(name);
            return *this;
        }

        Name& operator=(const std::string str) {
            super::assign(str);
            return *this;
        }
    };
} // namespace pepper
