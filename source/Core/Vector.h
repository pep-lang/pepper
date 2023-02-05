
#pragma once

#include <algorithm>

#include "llvm/ADT/SmallVector.h"

namespace pepper {
    template <typename T, unsigned int N = 0>
    struct Vector : public llvm::SmallVector<T, N> {
        using Super = llvm::SmallVector<T, N>;
        using llvm::SmallVector<T, N>::SmallVector;
        using llvm::SmallVector<T, N>::operator=;

        void remove(const T& item) {
            auto it = std::remove(this->begin(), this->end(), item);
            if (it != this->end())
                this->erase();
        }

        void remove_if(std::function<bool(const T&)> pred) {
            auto it = std::remove_if(this->begin(), this->end(), pred);
            if (it != this->end())
                this->erase(it);
        }
    };
} // namespace pepper