
#pragma once

#include "Compiler/Value.h"

namespace pepper {
    class Function : public Value {};

    class ExternFunction : public Function {};

    class UserFunction : public Function {};

} // namespace pepper
