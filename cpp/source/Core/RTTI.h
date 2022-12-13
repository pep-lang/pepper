#pragma once

#include <typeinfo>

class RTTI {
    const char* Name;
    RTTI* Base;

  public:
    RTTI(RTTI* base = nullptr, const char* name = nullptr)
        : Base(base)
        , Name(name) {}

    const RTTI* base() const { return Base; }

    bool is(const RTTI* other) const {
        if (this == other)
            return true;
        if (Base)
            return Base->is(other);
        return false;
    }

    struct None {};
};

template <typename T = RTTI::None> class RttiInstance : public RTTI {
  public:
    RttiInstance(RTTI* base = nullptr, const char* name = nullptr)
        : RTTI(base, name) {
        rtti = this;
    }

    inline static RTTI* rtti = nullptr;
};

#define DECLARE_RTTI(T, ...)                                                                                           \
    static RttiInstance<Type> _rtti_tag;                                                                               \
    const RTTI* _rtti() const {                                                                                        \
        if (!_rtti_tag.rtti)                                                                                           \
            new (&_rtti_tag) RttiInstance<Type>(RttiInstance<>::rtti, "Type");                                         \
        return &_rtti_tag;                                                                                             \
    }                                                                                                                  \
    template <typename Base> bool is() {                                                                               \
        auto thisTy = _rtti();                                                                                         \
        auto baseTy = RttiInstance<Base>::rtti;                                                                        \
        return thisTy->is(baseTy);                                                                                     \
    }                                                                                                                  \
    template <typename To> To as() {                                                                                   \
        if (this->is<To>()) {                                                                                          \
            return static_cast<To>(this);                                                                              \
        }                                                                                                              \
        return nullptr;                                                                                                \
    }
