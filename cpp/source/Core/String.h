//
// Created by Justin Boswell on 12/26/22.
//

#pragma once

#include <algorithm>
#include <cctype>
#include <functional>
#include <locale>
#include <string>

namespace pepper {
#define WHITESPACE " \t\n\r\f\v"

    // trim from end of string (right)
    inline std::string rtrim(const std::string& s, const char* t = WHITESPACE) {
        auto trimmed = s;
        trimmed.erase(trimmed.find_last_not_of(t) + 1);
        return trimmed;
    }

    // trim from beginning of string (left)
    inline std::string ltrim(const std::string& s, const char* t = WHITESPACE) {
        auto trimmed = s;
        trimmed.erase(0, trimmed.find_first_not_of(t));
        return trimmed;
    }

    // trim from both ends of string (right then left)
    inline std::string trim(const std::string& s, const char* t = WHITESPACE) {
        return ltrim(rtrim(s, t), t);
    }

#undef WHITESPACE
} // namespace pepper
