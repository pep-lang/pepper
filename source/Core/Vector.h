//
// Created by Justin Boswell on 12/25/22.
//

#pragma once

#include <algorithm>

#include "llvm/ADT/SmallVector.h"

namespace pepper {
    template <typename T>
    struct Vector : public llvm::SmallVector<T> {
        using Super = llvm::SmallVector<T>;
        using llvm::SmallVector<T>::SmallVector;
        using llvm::SmallVector<T>::operator=;

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