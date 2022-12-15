
#pragma once

#include "Core/RTTI.h"
#include <memory>

namespace pepper {
    template <typename T> struct Ref : public std::shared_ptr<T> {
        using std::shared_ptr<T>::operator=;

        Ref(std::shared_ptr<T>&& ptr)
            : std::shared_ptr<T>::shared_ptr(ptr) {
        }

        template <typename U>
        // requires HasRtti<T> && HasRtti<U>
        Ref<U> as() {
            return std::static_pointer_cast<U>(*this);
        }

        template <typename... Args> static Ref<T> create(Args&&... args) {
            return std::make_shared<T>(std::forward<decltype(args)>(args)...);
        }
    };

    template <typename T> struct WeakRef : public std::weak_ptr<T> {
        using std::weak_ptr<T>::operator=;

        template <typename U>
        // requires HasRtti<T> && HasRtti<U>
        Ref<U> as() {
            return std::static_pointer_cast<U>(*this);
        }
    };
} // namespace pepper
