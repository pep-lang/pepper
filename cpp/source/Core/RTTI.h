#pragma once

#include <concepts>
#include <type_traits>

namespace pepper {

    class RTTI {
        const char* Name;
        const RTTI* Base;

      public:
        constexpr RTTI(const RTTI* base = nullptr, const char* name = nullptr)
            : Base(base)
            , Name(name) {
        }

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
            constexpr const RTTI* rtti() const {
                return nullptr;
            }
        };

        template <typename T> static constexpr const RTTI* of() {
            return static_cast<T*>(nullptr)->rtti();
        }

        template <typename T> static const RTTI* of(const T t) {
            return of<std::remove_cvref_t<std::remove_pointer_t<T>>>();
        }
    };

    template <typename T = RTTI::None> class RttiInstance : public RTTI {
      private:
        RttiInstance() = delete;

        inline static RTTI* rtti = nullptr;

      public:
        inline static const RTTI* get(const RTTI* base, const char* name) {
            static std::aligned_storage_t<sizeof(RTTI)> _rtti;
            if (!rtti)
                rtti = new (&_rtti) RTTI(base, name);
            return rtti;
        }
    };

    template <> class RttiInstance<RTTI::None> {
      public:
        inline static constexpr const RTTI* get(const RTTI* base, const char* name) {
            return nullptr;
        }
    };

    template <typename T = RTTI::None> struct RttiType {
        using type = T;
    };

    template <typename T = RTTI::None> using rtti_type_t = typename RttiType<T>::type;

} // namespace pepper

#define DECLARE_RTTI(T, ...)                                                                                           \
  public:                                                                                                              \
    const pepper::RTTI* rtti() const {                                                                                 \
        return pepper::RttiInstance<T>::get(pepper::RTTI::of<pepper::rtti_type_t<__VA_ARGS__>>(), #T);                 \
    }                                                                                                                  \
    template <typename Base> bool is() {                                                                               \
        auto thisTy = rtti();                                                                                          \
        auto baseTy = pepper::RTTI::of<Base>();                                                                        \
        return thisTy->is(baseTy);                                                                                     \
    }                                                                                                                  \
    template <typename To> To as() {                                                                                   \
        if (this->is<To>()) {                                                                                          \
            return static_cast<To>(this);                                                                              \
        }                                                                                                              \
        return nullptr;                                                                                                \
    }
