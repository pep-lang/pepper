//
// Created by Justin Boswell on 12/24/22.
//

#pragma once

#include "Core/Vector.h"
#include "llvm/ADT/ArrayRef.h"

namespace pepper {
    template <typename T>
    struct QueryInst;

    template <typename T>
    QueryInst<T> Query(llvm::ArrayRef<T> arr);

    template <typename T>
    QueryInst<T> Query(const Vector<T>& arr);

    template <typename T>
    struct QueryInst {
        Vector<T> Src;
        llvm::ArrayRef<T> Ref;

        friend QueryInst<T> Query<T>(llvm::ArrayRef<T>);
        friend QueryInst<T> Query<T>(const Vector<T>&);

        /* implicit */ QueryInst(llvm::ArrayRef<T> ref)
            : Ref(ref) {
        }

        // just reference the incoming vector
        /* implicit */ QueryInst(const Vector<T>& src)
            : Ref(src) {
        }

        explicit QueryInst(Vector<T>&& src)
            : Src(std::move(src))
            , Ref(Src) {
        }

        // used internally to move from one operation to the next
        explicit QueryInst(QueryInst<T>&& src)
            : Src(std::move(src))
            , Ref(Src) {
        }

      public:
        template <typename U>
        QueryInst<U> select(std::function<U(const T&)> selector) {
            Vector<U> results;
            std::transform(Ref.begin(), Ref.end(), std::back_inserter(results), selector);
            return QueryInst<U>(std::move(results));
        }

        QueryInst where(std::function<bool(const T&)> selector) {
            Vector<T> results;
            std::copy_if(Ref.begin(), Ref.end(), std::back_inserter(results), selector);
            return QueryInst(std::move(results));
        }

        QueryInst without(std::function<bool(const T&)> selector) {
            Vector<T> results;
            std::copy_if(Ref.begin(), Ref.end(), std::back_inserter(results), [&selector](const T& item) {
                return !selector(item);
            });
            return QueryInst(std::move(results));
        }

        QueryInst& concat(llvm::ArrayRef<T> rhs) {
            if (Ref.size() != Src.size()) {
                std::copy(Ref.begin(), Ref.end(), std::back_inserter(Src));
                Ref = Src;
            }
            std::copy(rhs.begin(), rhs.end(), std::back_inserter(Ref));
            return *this;
        }

        void each(std::function<void(const T&)> func) {
            std::for_each(Ref.begin(), Ref.end(), func);
        }

        operator Vector<T>() {
            return Vector<T>(Ref.begin(), Ref.end());
        }
    };

    template <typename T>
    QueryInst<T> Query(llvm::ArrayRef<T> arr) {
        return arr;
    }

    template <typename T>
    QueryInst<T> Query(const Vector<T>& arr) {
        return arr;
    }
} // namespace pepper
