
#pragma once

#include <memory>
#include <string>

class Codegen;

struct SourceLocation {
    const std::string File;
    const int Line;

    SourceLocation(const std::string& file, int line)
        : File(file)
        , Line(line) {
    }

    std::string toString() const;
};

class Parser {
  public:
    Parser() = default;
    ~Parser() = default;

    void parse(std::istream& stream, const std::string& name = "");
};
