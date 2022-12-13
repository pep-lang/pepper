
#pragma once

#include <memory>

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
} // namespace llvm

class Value {};

using ValueRef = std::shared_ptr<Value>;
