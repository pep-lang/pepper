

#pragma once

#include <cstdint>
#include <optional>

#include "Core/Vector.h"

namespace pepper {

    template <typename T, typename It = decltype(std::declval<const Vector<T, 0>>().begin())>
    struct Query {
        Vector<T, 0> Storage;
        const Vector<T, 0>* Src;
        It Begin;
        It End;

        Query(It beginIt, It endIt)
            : Begin(beginIt)
            , End(endIt) {}

        // Construct from Vector
        template <unsigned int N>
        explicit Query(const Vector<T, N>& src)
            : Src(&src)
            , Begin(Src->begin())
            , End(Src->end()) {}

        // construct from std::vector
        explicit Query(const std::vector<T>& src)
            : Storage(src.begin(), src.end())
            , Src(&Storage)
            , Begin(Storage.begin())
            , End(Storage.end()) {}

        // used internally to move from one operation to the next
        template <unsigned int N>
        Query(Vector<T, N>&& src)
            : Storage(std::move(src))
            , Src(&Storage)
            , Begin(Storage.begin())
            , End(Storage.end()) {}

        // used internally to move from one operation to the next
        Query(Query&& src) noexcept
            : Storage(std::move(src.Src))
            , Src(&Storage)
            , Begin(Src->begin())
            , End(Src->end()) {}

        It begin() const {
            return Begin;
        }

        It end() const {
            return End;
        }

        template <typename U>
        Query<U> select(std::function<U(const T&)>&& selector) const {
            Vector<U> results;
            std::transform(begin(), end(), std::back_inserter(results), selector);
            return {std::move(results)};
        }

        template <typename U>
        Query<U> select() const {
            Vector<U> results;
            std::transform(begin(), end(), std::back_inserter(results), [](const T& e) { return U{e}; });
            return {std::move(results)};
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

        Query range(size_t start, int64_t len = -1) const {
            Vector<T> results;
            auto startIt = begin() + start;
            len = (len == -1) ? std::distance(startIt, end()) : len;
            std::copy_n(startIt, len, std::back_inserter(results));
            return std::move(results);
        }

        Query& concat(It beginIt, It endIt) {
            std::copy(beginIt, endIt, std::back_inserter(*Src));
            return *this;
        }

        Query& concat(llvm::ArrayRef<T> rhs) {
            return concat(rhs.begin(), rhs.end());
        }

        int64_t index_of(const T& item, size_t startIndex = 0) const {
            auto it = std::find(begin() + startIndex, end(), item);
            if (it != end()) {
                return std::distance(begin(), it);
            }
            return -1;
        }

        int64_t index_of(std::function<bool(const T&)> pred, size_t startIndex = 0) const {
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
            return std::move(Storage);
        }
    };

    template <typename T>
    Query(const std::vector<T>& v) -> Query<T>;

    template <typename T, unsigned int N>
    Query(const Vector<T, N>& v) -> Query<T, decltype(v.begin())>;

    template <typename T, unsigned int N>
    Query(Vector<T, N>&& v) -> Query<T, decltype(v.begin())>;
} // namespace pepper
