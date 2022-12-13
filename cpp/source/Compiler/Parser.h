
#pragma once

#include "Codegen.h"

#include <memory>

class Parser {
  private:
    std::shared_ptr<class Codegen> Generator;

  public:
    Parser(std::shared_ptr<Codegen> gen) : Generator(gen) {}

    ~Parser() = default;

    void Parse(std::istream& stream);
};
