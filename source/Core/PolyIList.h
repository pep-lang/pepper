//
// Created by Justin Boswell on 1/21/23.
//

#pragma once

#include <cassert>
#include <iterator>

namespace pepper {
    template <typename T>
    struct poly_ilist_node {
        poly_ilist_node* Next = nullptr;
        poly_ilist_node* Prev = nullptr;
        bool Sentinel = false;

        poly_ilist_node() = default;
        poly_ilist_node(const poly_ilist_node&) = delete;
        poly_ilist_node(poly_ilist_node&&) = delete;
        poly_ilist_node& operator=(const poly_ilist_node&) = delete;

        bool isSentinel() const {
            return Sentinel;
        }
    };

    template <typename T>
    struct poly_ilist_sentinel : public poly_ilist_node<T> {
        poly_ilist_sentinel() {
            this->Sentinel = true;
            reset();
        }

        bool empty() const {
            return this == this->Prev;
        }

        void reset() {
            this->Prev = this;
            this->Next = this;
        }
    };

    template <typename T, typename N, bool IsReverse, bool IsConst>
    class poly_ilist_iterator {
        friend poly_ilist_iterator<T, N, IsReverse, !IsConst>;
        friend poly_ilist_iterator<T, N, !IsReverse, IsConst>;
        friend poly_ilist_iterator<T, N, !IsReverse, !IsConst>;

      public:
        using value_type = T;
        using pointer = T*;
        using reference = T&;
        using difference_type = ptrdiff_t;
        using iterator_category = std::bidirectional_iterator_tag;
        using const_pointer = const T*;
        using const_reference = const T&;

      private:
        using node_pointer = poly_ilist_node<N>*;
        using node_reference = poly_ilist_node<N>&;
        using const_node_pointer = const poly_ilist_node<N>*;
        using node_type_pointer = N*;
        using node_type_reference = N&;

        node_pointer It = nullptr;

      public:
        explicit poly_ilist_iterator(node_reference n)
            : It(&n) {
        }

        explicit poly_ilist_iterator(node_type_pointer pt)
            : It(pt) {
        }

        explicit poly_ilist_iterator(reference rt)
            : It(&rt) {
        }

        explicit poly_ilist_iterator(const poly_ilist_sentinel<N>& rs)
            : It(const_cast<node_pointer>(static_cast<const_node_pointer>(&rs))) {
        }

        poly_ilist_iterator() = default;

        template <bool RhsConst>
        poly_ilist_iterator(const poly_ilist_iterator<T, N, IsReverse, RhsConst>& rhs,
                            std::enable_if_t<IsConst || !RhsConst, void*> = nullptr)
            : It(rhs.It) {
        }

        template <bool RhsConst>
        std::enable_if_t<IsConst || !RhsConst, poly_ilist_iterator&> operator=(
            const poly_ilist_iterator<T, N, IsReverse, RhsConst>& rhs) {
            It = rhs.It;
            return *this;
        }

        explicit poly_ilist_iterator(const poly_ilist_iterator<T, N, !IsReverse, IsConst>& rhs)
            : poly_ilist_iterator(++rhs.reverse()) {
        }

        poly_ilist_iterator<T, N, !IsReverse, IsConst> reverse() const {
            if (It)
                return poly_ilist_iterator<T, N, !IsReverse, IsConst>(*It);
            return poly_ilist_iterator<T, N, !IsReverse, IsConst>{};
        }

        poly_ilist_iterator<T, N, IsReverse, false> asNonConst() const {
            if (It)
                return poly_ilist_iterator<T, N, IsReverse, false>{
                    const_cast<typename poly_ilist_iterator<T, N, IsReverse, false>::node_Reference>(*It)};
            return poly_ilist_iterator<T, N, IsReverse, false>{};
        }

        reference operator*() const {
            assert(!It->isSentinel());
            return *static_cast<pointer>(It);
        }

        pointer operator->() const {
            return &operator*();
        }

        friend bool operator==(const poly_ilist_iterator& lhs, const poly_ilist_iterator& rhs) {
            return lhs.It == rhs.It;
        }

        friend bool operator!=(const poly_ilist_iterator& lhs, const poly_ilist_iterator& rhs) {
            return lhs.It != rhs.It;
        }

        poly_ilist_iterator operator++() {
            It = IsReverse ? It->Prev : It->Next;
            return *this;
        }

        poly_ilist_iterator operator++(int) {
            auto ret = *this;
            ++*this;
            return ret;
        }

        poly_ilist_iterator operator--() {
            It = IsReverse ? It->Next : It->Prev;
            return *this;
        }

        poly_ilist_iterator operator--(int) {
            auto ret = *this;
            --*this;
            return ret;
        }

        pointer value() const {
            return static_cast<pointer>(It);
        }

        bool isEnd() const {
            return It ? It->isSentinel() : false;
        }
    };

    // This is virtually identical to llvm::ilist, except that it always takes ownership and allows a list of T
    // to store any object that is polymorphically convertible to T. insert/splice take ownership of the source
    // nodes after detaching them from their prior list (if applicable)
    template <typename T, typename N = T>
    class poly_ilist {
        static_assert(std::is_convertible_v<T*, N*>, "Node type must derive from list element type");
        typedef poly_ilist_node<N> node_type;

      private:
        poly_ilist_sentinel<N> Sentinel;

      public:
        using value_type = T;
        using pointer = T*;
        using reference = T&;
        using const_pointer = const T*;
        using const_reference = const T&;
        using iterator = poly_ilist_iterator<T, N, false, false>;
        using const_iterator = poly_ilist_iterator<T, N, false, true>;
        using reverse_iterator = poly_ilist_iterator<T, N, true, false>;
        using const_reverse_iterator = poly_ilist_iterator<T, N, true, true>;
        using size_type = size_t;
        using difference_type = ptrdiff_t;

        poly_ilist() = default;
        poly_ilist(const poly_ilist&) = delete;
        poly_ilist& operator=(const poly_ilist&) = delete;

        ~poly_ilist() {
            clear();
        }

        poly_ilist(poly_ilist&& src) {
            splice(end(), src);
        }

        poly_ilist(std::initializer_list<pointer> il) {
            for (auto pt : il)
                push_back(*pt);
        }

        poly_ilist& operator=(poly_ilist&& src) {
            clear();
            splice(end(), src);
            return *this;
        }

        iterator begin() {
            return ++iterator(Sentinel);
        }

        iterator end() {
            return iterator(Sentinel);
        }

        const_iterator begin() const {
            return ++const_iterator(Sentinel);
        }

        const_iterator end() const {
            return const_iterator(Sentinel);
        }

        reverse_iterator rbegin() {
            return ++reverse_iterator(Sentinel);
        }

        reverse_iterator rend() {
            return reverse_iterator(Sentinel);
        }

        const_reverse_iterator rbegin() const {
            return ++const_reverse_iterator(Sentinel);
        }

        const_reverse_iterator rend() const {
            return const_reverse_iterator(Sentinel);
        }

        bool empty() const {
            return Sentinel.empty();
        }

        size_t size() const {
            return std::distance(begin(), end());
        }

        reference front() {
            return *begin();
        }

        const_reference front() const {
            return *begin();
        }

        reference back() {
            return *--end();
        }

        const_reference back() const {
            return *--end();
        }

        void push_front(reference node) {
            insert(begin(), node);
        }

        void push_back(reference node) {
            insert(end(), node);
        }

        void pop_front() {
            erase(begin());
        }

        void pop_back() {
            erase(--end());
        }

        void insert(iterator it, reference node) {
            insert(*it.value(), node);
        }

        template <class Iter>
        void insert(iterator it, Iter first, Iter last) {
            for (; first != last; ++first)
                insert(it, *first);
        }

        template <class Clone>
        void clone(const poly_ilist& src, Clone cloneNode) {
            clear();
            for (const auto& n : src)
                push_back(*cloneNode(n));
        }

        void splice(iterator it, poly_ilist& src) {
            splice(it, src.begin(), src.end());
        }

        void splice(iterator it, iterator first, iterator last) {
            transfer(*it.value(), *first.value(), *last.value());
        }

        void append(poly_ilist& src) {
            splice(end(), src);
        }

        template <class Iter>
        void append(Iter first, Iter last) {
            insert(end(), first, last);
        }

        void remove(reference it) {
            auto prev = it.Prev;
            auto next = it.Next;
            next->Prev = prev;
            prev->Next = next;
            it.Next = it.Prev = nullptr;
        }

        iterator erase(iterator it) {
            assert(it != end() && "Cannot remove sentinel");
            auto next = std::next(it);
            remove(*it);
            delete &*it;
            return next;
        }

        iterator erase(iterator first, iterator last) {
            while (first != last)
                first = erase(first);
            return last;
        }

        void clear() {
            erase(begin(), end());
        }

        void swap(poly_ilist& other) {
            std::swap(*this, other);
        }

      private:
        void transfer(node_type& next, node_type& first, node_type& last) {
            if (&next == &last || &first == &last)
                return;

            assert(&next != &first && "Insertion point can't be one of the transferred nodes");

            auto& final = *last.Prev;

            first.Prev->Next = &last;
            last.Prev = first.Prev;

            auto& prev = *next.Prev;
            final.Next = &next;
            first.Prev = &prev;
            prev.Next = &first;
            next.Prev = &final;
        }

        void insert(reference next, reference node) {
            node_type& prev = *next.Prev;

            // extract the node from any prior list
            if (node.Prev)
                node.Prev->Next = node.Next;
            if (node.Next)
                node.Next->Prev = node.Prev;

            node.Next = &next;
            node.Prev = &prev;
            prev.Next = &node;
            next.Prev = &node;
        }

        void removeRange(node_type& first, node_type& last) {
            node_type* prev = first.Prev;
            node_type* final = last.Prev;
            last.Prev = prev;
            prev->Next = &last;

            first.Prev = nullptr;
            final->Next = nullptr;
        }
    };
} // namespace pepper
