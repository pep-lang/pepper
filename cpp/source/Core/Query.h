//
// Created by Justin Boswell on 12/24/22.
//

#pragma once

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace pepper {
    template <typename T>
    struct QueryInst;

    template <typename T>
    QueryInst<T> Query(const llvm::ArrayRef<T>& arr);

    template <typename T>
    struct QueryInst {
        template <typename E>
        using Vector = llvm::SmallVector<E>;

        Vector<T> Src;

        friend QueryInst<T> Query<T>(const llvm::ArrayRef<T>&);

        explicit QueryInst(const llvm::ArrayRef<T>& src)
            : Src(src) {
        }

        // used internally to move from one operation to the next
        explicit QueryInst(Vector<T>&& src)
            : Src(std::move(src)) {
        }

      public:
        template <typename U>
        QueryInst<U> select(std::function<U(const T&)> selector) {
            Vector<U> results;
            std::transform(Src.begin(), Src.end(), std::back_inserter(results), selector);
            return QueryInst<U>(std::move(results));
        }

        QueryInst where(std::function<bool(const T&)> selector) {
            Vector<T> results;
            std::copy_if(Src.begin(), Src.end(), std::back_inserter(results), selector);
            return QueryInst(std::move(results));
        }

        void each(std::function<void(const T&)> func) {
            std::for_each(Src.begin(), Src.end(), func);
        }

        Vector<T>&& vector() const {
            return std::move(Src);
        }
    };

    template <typename T>
    QueryInst<T> Query(const llvm::ArrayRef<T>& arr) {
        return QueryInst<T>(arr);
    }
} // namespace pepper
