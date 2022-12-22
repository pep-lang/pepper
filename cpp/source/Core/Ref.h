//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <memory>

namespace pepper {
    template <typename T> struct Ref : public std::shared_ptr<T> {
        using base = std::shared_ptr<T>;
        using std::shared_ptr<T>::shared_ptr;

        Ref(std::shared_ptr<T>&& ptr)
            : base(ptr) {
        }

        template <typename U>
        Ref(Ref<U> ref)
            : base(ref.template as<T>()) {
        }

        template <typename U>
        // requires HasRtti<T> && HasRtti<U>
        Ref<U> as() {
            return std::static_pointer_cast<U>(*this);
        }

        template <class... Args> static Ref<T> create(Args&&... args) {
            return std::make_shared<T>(std::forward<Args>(args)...);
        }
    };

    template <typename T> struct WeakRef : public std::weak_ptr<T> {
        using std::weak_ptr<T>::weak_ptr;
        using std::weak_ptr<T>::operator=;

        template <typename U>
        // requires HasRtti<T> && HasRtti<U>
        Ref<U> as() {
            return std::static_pointer_cast<U>(*this);
        }
    };
}
