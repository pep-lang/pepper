#pragma once

#include <concepts>
#include <typeinfo>

namespace pepper {
    class RTTI;

    template <typename T>
    concept HasRtti = requires(T t) {
                          { T::_rtti_tag } -> std::convertible_to<RTTI>;
                      };

    class RTTI {
        const char* Name;
        RTTI* Base;

      public:
        RTTI(RTTI* base = nullptr, const char* name = nullptr)
            : Base(base)
            , Name(name) {
        }

        const char* name() const {
            return Name;
        }

        const RTTI* base() const {
            return Base;
        }

        bool is(const RTTI* other) const {
            if (this == other)
                return true;
            if (Base)
                return Base->is(other);
            return false;
        }

        struct None {};

        template <typename T>
            requires HasRtti<T>
        static const RTTI& of() {
            return T::_rtti_tag;
        }

        template <typename T>
            requires HasRtti<T>
        static const RTTI& of(const T t) {
            return of<std::remove_cvref_t<T>>();
        }
    };

    template <typename T = RTTI::None> class RttiInstance : public RTTI {
      public:
        RttiInstance(RTTI* base = nullptr, const char* name = nullptr)
            : RTTI(base, name) {
            rtti = this;
        }

        inline static RTTI* rtti = nullptr;
    };

} // namespace pepper

#define DECLARE_RTTI(T, ...)                                                                                           \
  public:                                                                                                              \
    static pepper::RttiInstance<T> _rtti_tag;                                                                          \
    const pepper::RTTI* _rtti() const {                                                                                \
        if (!_rtti_tag.rtti)                                                                                           \
            new (&_rtti_tag) pepper::RttiInstance<T>(RttiInstance<>::rtti, "Type");                                    \
        return &_rtti_tag;                                                                                             \
    }                                                                                                                  \
    template <typename Base> bool is() {                                                                               \
        auto thisTy = _rtti();                                                                                         \
        auto baseTy = pepper::RttiInstance<Base>::rtti;                                                                \
        return thisTy->is(baseTy);                                                                                     \
    }                                                                                                                  \
    template <typename To> To as() {                                                                                   \
        if (this->is<To>()) {                                                                                          \
            return static_cast<To>(this);                                                                              \
        }                                                                                                              \
        return nullptr;                                                                                                \
    }
