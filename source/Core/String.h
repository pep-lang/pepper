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

    inline std::string replace(const std::string& s, const std::string& search, const std::string& replacement) {
        auto res = s;
        auto pos = res.find(search);
        if (pos != -1)
            res.replace(pos, search.size(), replacement);
        return res;
    }

    inline std::string replace_all(const std::string& s, const std::string& search, const std::string& replacement) {
        auto res = s;
        size_t pos = 0;
        while (pos != std::string::npos) {
            pos = res.find(search, pos);
            if (pos != std::string::npos) {
                res.replace(pos, search.size(), replacement);
                ++pos;
            }
        }
        return res;
    }

    inline std::string repeat(const std::string& str, size_t n) {
        std::string res;
        for (int idx = 0; idx < n; ++idx) {
            res += str;
        }
        return res;
    }

    inline std::string rpad(const std::string& s, size_t width) {
        if (s.size() >= width)
            return s;
        return s + repeat(" ", width - s.size());
    }

    inline std::string indent(const std::string& s, size_t width) {
        auto prefix = repeat(" ", width);
        auto linePrefix = "\n" + prefix;
        return replace_all(s, "\n", linePrefix);
    }
} // namespace pepper
