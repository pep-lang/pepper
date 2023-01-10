#pragma once

#include <concepts>
#include <type_traits>

namespace pepper {

    class RTTI {
        const char* Name;
        const RTTI* Base;

      protected:
        constexpr RTTI(const RTTI* base = nullptr, const char* name = nullptr)
            : Base(base)
            , Name(name) {
        }

      public:
        constexpr const char* name() const {
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

        inline static RttiInstance<T>* rtti = nullptr;

      public:
        inline static const RttiInstance<T>* get(const RTTI* base, const char* name) {
            static std::aligned_storage_t<sizeof(RttiInstance<T>)> _rtti;
            if (!rtti)
                rtti = new (&_rtti) RttiInstance<T>(base, name);
            return rtti;
        }

        inline T* clone(const T* t) const {
            return new T(*t);
        }

        //        template <typename... Args>
        //        inline T* clone(Args&&... args) const {
        //            return new T(std::forward<Args>(args)...);
        //        }

        template <typename U>
        inline T* downcast(U* u) const {
            return static_cast<T*>(u);
        }

        template <typename U>
        inline const T* downcast(const U* u) const {
            return static_cast<const T*>(u);
        }
    };

    template <>
    class RttiInstance<RTTI::None> {
      public:
        inline static constexpr const RTTI* get(const RTTI*, const char*) {
            return nullptr;
        }
    };

    template <typename T = RTTI::None>
    struct RttiType {
        using type = T;
    };

    template <typename T = RTTI::None>
    using rtti_type_t = typename RttiType<T>::type;

    template <typename T>
    concept HasRtti = requires(T* t) { t->rtti(); };

} // namespace pepper

#define DECLARE_RTTI_COMMON(T)                                                                                         \
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
        return const_cast<T*>(this)->as<To>();                                                                         \
    }

#define DECLARE_RTTI_IMPL(T, ...)                                                                                      \
    static const pepper::RttiInstance<T>* _rtti() {                                                                    \
        return pepper::RttiInstance<T>::get(pepper::RTTI::of<pepper::rtti_type_t<>>(), #T);                            \
    }                                                                                                                  \
    virtual const pepper::RTTI* rtti() const {                                                                         \
        return _rtti();                                                                                                \
    }

#define DECLARE_RTTI_IMPL_DERIVED(T, ...)                                                                              \
    static const pepper::RttiInstance<T>* _rtti() {                                                                    \
        return pepper::RttiInstance<T>::get(pepper::RTTI::of<pepper::rtti_type_t<__VA_ARGS__>>(), #T);                 \
    }                                                                                                                  \
    const pepper::RTTI* rtti() const override {                                                                        \
        return _rtti();                                                                                                \
    }

#define DECLARE_RTTI(T, ...)                                                                                           \
  public:                                                                                                              \
    DECLARE_RTTI_IMPL##__VA_OPT__(_DERIVED)(T, __VA_ARGS__) DECLARE_RTTI_COMMON(T)
