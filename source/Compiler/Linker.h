
#pragma once

#include <string>

#include "Compiler/Options.h"
#include "Core/Vector.h"

namespace pepper {
    class Linker {
      public:
        static void link(Ref<Options> opts, const Vector<std::string>& objFiles);
    };
} // namespace pepper
