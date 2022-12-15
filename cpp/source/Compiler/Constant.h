#pragma once

#include "Compiler/Value.h"

namespace pepper {
    class Constant : public Value {};

    class ConstantInt : public Constant {};

    class ConstantFloat : public Constant {};

    class ConstantString : public Constant {};
} // namespace pepper
