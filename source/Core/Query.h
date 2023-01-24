//
// Created by Justin Boswell on 12/24/22.
//

#pragma once

#include <optional>

#include "Core/PolyIList.h"
#include "Core/Vector.h"

namespace pepper {

    template <typename T, typename It = decltype(std::declval<const Vector<T, 0>>().begin())>
    struct Query {
        Vector<T, 0> Src;
        It Begin;
        It End;

        Query(It beginIt, It endIt)
            : Begin(beginIt)
            , End(endIt) {
        }

        // Construct from Vector
        template <unsigned int N>
        explicit Query(const Vector<T, N>& src)
            : Query(src.begin(), src.end()) {
        }

        // Construct from poly_ilist
        template <typename N>
        explicit Query(const poly_ilist<T, N>& src)
            : Query(src.begin(), src.end()) {
        }

        // construct from std::vector
        explicit Query(const std::vector<T>& src)
            : Query(src.begin(), src.end()) {
        }

        // used internally to move from one operation to the next
        template <unsigned int N>
        explicit Query(Vector<T, N>&& src)
            : Src(std::move(src))
            , Begin(Src.begin())
            , End(Src.end()) {
        }

        // used internally to move from one operation to the next
        explicit Query(Query&& src) noexcept
            : Src(std::move(src))
            , Begin(Src.begin())
            , End(Src.end()) {
        }

      public:
        It begin() const {
            return Begin;
        }

        It end() const {
            return End;
        }

        template <typename U>
        Query<U> select(std::function<U(const T&)> selector = [](const auto& e) { return U{e}; }) const {
            Vector<U> results;
            std::transform(begin(), end(), std::back_inserter(results), selector);
            return Query<U>(std::move(results));
        }

        Query map(std::function<T(const T&)> func) {
            Vector<T> results;
            std::transform(begin(), end(), std::back_inserter(results), func);
            return Query(std::move(results));
        }

        Query where(std::function<bool(const T&)> selector) const {
            Vector<T> results;
            std::copy_if(begin(), end(), std::back_inserter(results), selector);
            return Query(std::move(results));
        }

        Query without(std::function<bool(const T&)> selector) const {
            Vector<T> results;
            std::copy_if(
                begin(), end(), std::back_inserter(results), [&selector](const T& item) { return !selector(item); });
            return std::move(results);
        }

        Query range(size_t start, ssize_t len = -1) const {
            Vector<T> results;
            auto startIt = begin() + start;
            len = (len == -1) ? std::distance(startIt, end()) : len;
            std::copy_n(startIt, len, std::back_inserter(results));
            return std::move(results);
        }

        Query& concat(It beginIt, It endIt) {
            std::copy(beginIt, endIt, std::back_inserter(Src));
            return *this;
        }

        Query& concat(llvm::ArrayRef<T> rhs) {
            return concat(rhs.begin(), rhs.end());
        }

        ssize_t indexOf(const T& item, size_t startIndex = 0) const {
            auto it = std::find(begin() + startIndex, end(), item);
            if (it != end()) {
                return std::distance(begin(), it);
            }
            return -1;
        }

        ssize_t indexOf(std::function<bool(const T&)> pred, size_t startIndex = 0) const {
            auto it = std::find_if(begin() + startIndex, end(), pred);
            if (it != end()) {
                return std::distance(begin(), it);
            }
            return -1;
        }

        Query& each(std::function<void(const T&)> func) {
            std::for_each(begin(), end(), func);
            return *this;
        }

        std::optional<T> find(std::function<bool(const T&)> pred) const {
            auto it = std::find_if(begin(), end(), pred);
            if (it != end()) {
                return *it;
            }
            return {};
        }

        operator Vector<T>() {
            return toVector();
        }

        Vector<T> toVector() {
            return Vector<T>{begin(), end()};
        }
    };

    template <typename T>
    Query(const std::vector<T>& v) -> Query<T, decltype(v.begin())>;

    template <typename T>
    Query(const Vector<T>& v) -> Query<T, decltype(v.begin())>;

    template <typename T>
    Query(Vector<T>&& v) -> Query<T, decltype(v.begin())>;

    template <typename T, typename N>
    Query(const poly_ilist<T, N>& list) -> Query<T, decltype(list.begin())>;
} // namespace pepper
