#pragma once

#include "llvm/Support/TypeName.h"

#include <type_traits>

namespace pepper {

    class RTTI {
        const RTTI* Base;
        std::string_view Name;

      protected:
        constexpr RTTI(const RTTI* base = nullptr, std::string_view name = {})
            : Base(base)
            , Name(name) {}

      public:
        constexpr std::string_view name() const {
            return Name;
        }

        constexpr const RTTI* base() const {
            return Base;
        }

        constexpr bool is(const RTTI* other) const {
            if (this == other)
                return true;
            if (Base)
                return Base->is(other);
            return false;
        }

        template <typename T>
        constexpr bool is() const {
            return is(RTTI::of<T>());
        }

        struct None {
            static constexpr const RTTI* _rtti() {
                return nullptr;
            }
        };

        template <typename T>
        static constexpr const RTTI* of() {
            return T::_rtti();
        }

        template <typename T>
        static const RTTI* of(const T) {
            return of<std::remove_cvref_t<std::remove_pointer_t<T>>>();
        }
    };

    template <typename T = RTTI::None>
    class RttiInstance : public RTTI {
      private:
        RttiInstance() = delete;
        using RTTI::RTTI;

        inline static RttiInstance* rtti = nullptr;

      public:
        static const RttiInstance* get(const RTTI* base, std::string_view name) {
            static std::byte _rtti[sizeof(RttiInstance)];
            if (!rtti)
                rtti = new (&_rtti) RttiInstance(base, name);
            return rtti;
        }

        T* clone(const T* t) const {
            return new T(*t);
        }

        //        template <typename... Args>
        //        inline T* clone(Args&&... args) const {
        //            return new T(std::forward<Args>(args)...);
        //        }

        template <typename U>
        T* downcast(U* u) const {
            return static_cast<T*>(u);
        }

        template <typename U>
        const T* downcast(const U* u) const {
            return static_cast<const T*>(u);
        }
    };

    template <>
    class RttiInstance<RTTI::None> {
      public:
        static constexpr const RTTI* get(const RTTI*, const char*) {
            return nullptr;
        }
    };

    template <typename T = RTTI::None>
    struct RttiType {
        using type = T;
    };

    template <typename T = RTTI::None>
    using rtti_type_t = RttiType<T>::type;

    template <typename T>
    concept HasRtti = requires(std::remove_pointer_t<T> t) { t.rtti(); };

} // namespace pepper

#define DECLARE_RTTI_COMMON(Ty)                                                                                        \
    template <typename T>                                                                                              \
    bool is() const {                                                                                                  \
        auto thisTy = rtti();                                                                                          \
        auto tTy = pepper::RTTI::of<T>();                                                                              \
        return thisTy->is(tTy);                                                                                        \
    }                                                                                                                  \
    template <typename To>                                                                                             \
    std::add_pointer_t<To> as() {                                                                                      \
        if (this->is<To>()) {                                                                                          \
            return static_cast<std::add_pointer_t<To>>(this);                                                          \
        }                                                                                                              \
        return nullptr;                                                                                                \
    }                                                                                                                  \
    template <typename To>                                                                                             \
    const std::add_pointer_t<To> as() const {                                                                          \
        return const_cast<Ty*>(this)->as<To>();                                                                        \
    }

#define DECLARE_RTTI_IMPL(T, ...)                                                                                      \
    static const pepper::RttiInstance<T>* _rtti() {                                                                    \
        return pepper::RttiInstance<T>::get(pepper::RTTI::of<pepper::rtti_type_t<>>(),                                 \
                                            std::string_view{llvm::getTypeName<T>()});                                 \
    }                                                                                                                  \
    virtual const pepper::RTTI* rtti() const {                                                                         \
        return _rtti();                                                                                                \
    }

#define DECLARE_RTTI_IMPL_DERIVED(T, ...)                                                                              \
    static const pepper::RttiInstance<T>* _rtti() {                                                                    \
        return pepper::RttiInstance<T>::get(pepper::RTTI::of<pepper::rtti_type_t<__VA_ARGS__>>(),                      \
                                            std::string_view{llvm::getTypeName<T>()});                                 \
    }                                                                                                                  \
    const pepper::RTTI* rtti() const override {                                                                        \
        return _rtti();                                                                                                \
    }

#define DECLARE_RTTI(T, ...)                                                                                           \
  public:                                                                                                              \
    DECLARE_RTTI_IMPL##__VA_OPT__(_DERIVED)(T, __VA_ARGS__) DECLARE_RTTI_COMMON(T)
