
#pragma once

#include <memory>

class Codegen;

class Parser {
  private:
    std::shared_ptr<Codegen> Generator;

  public:
    Parser(std::shared_ptr<Codegen> gen)
        : Generator(gen) {}

    ~Parser() = default;

    void parse(std::istream& stream);
};
