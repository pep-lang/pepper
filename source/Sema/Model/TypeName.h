
#pragma once

#include "Core/Ident.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::sema {

    struct TypeName {
        enum TypeFlags {
            Scalar = 0,
            Array = 1,
            Function = 2,
        } Flags;

        Ident name;
        std::vector<TypeName> sub_types;

        constexpr TypeName(const Ident& name = {}, const std::vector<TypeName>& types = {}, const TypeFlags flags = Scalar)
            : Flags(flags)
              , name(name)
              , sub_types(types.begin(), types.end()) {}

        TypeName(const Ident& name, const Vector<TypeName>& types, const TypeFlags flags = Scalar)
            : Flags(flags)
            , name(name)
            , sub_types(types.begin(), types.end()) {}

        constexpr TypeName(const TypeName&) = default;
        constexpr TypeName(TypeName&&) noexcept = default;
        TypeName& operator=(const TypeName&) = default;

        bool empty() const {
            return name.empty() && sub_types.empty();
        }

        operator std::string() const {
            return to_string();
        }

        bool operator==(const TypeName& rhs) const {
            return Flags == rhs.Flags && name == rhs.name && sub_types == rhs.sub_types;
        }

        bool operator==(const std::string& str) const {
            return str == to_string();
        }

        bool operator!=(const TypeName& rhs) const {
            return !(*this == rhs);
        }

        bool is_scalar() const {
            return Flags == Scalar;
        }

        bool is_array() const {
            return Flags == Array;
        }

        bool is_function() const {
            return Flags == Function;
        }

        bool is_generic() const {
            return (Flags != Array && !sub_types.empty());
        }

        bool is_numeric() const {
            return is_integral() && *this != Auto && *this != Void;
        }

        bool is_struct() const;
        bool is_integral() const;
        bool is_pointer() const;

        const TypeName& element_type() const {
            assert(Flags == Array);
            assert(sub_types.empty());
            return *this;
        }

        std::string to_string() const;

        static constexpr TypeName make_array(const Ident& array_type, const TypeName& element_type) {
            return {array_type, std::vector{element_type}, Array};
        }

        static TypeName make_struct(const Ident& structTypeName, const Vector<TypeName>& subTypes = {}) {
            return {structTypeName, subTypes};
        }

        static TypeName make_function(const Ident& name, const Vector<TypeName>& genericArgs = {}) {
            return {name, genericArgs, Function};
        }

        static const TypeName& widest(const TypeName& lhs, const TypeName& rhs);

        static const TypeName Empty;

        static const TypeName Void;
        static const TypeName Auto;
        static const TypeName Bool;

        static const TypeName VoidPtr;
        static const TypeName Int8;
        static const TypeName UInt8;
        static const TypeName Int32;
        static const TypeName UInt32;
        static const TypeName Int64;
        static const TypeName UInt64;
        static const TypeName Double;
        static const TypeName Float;

        static llvm::StringSet<> IntegralTypes;
    };
} // namespace pepper::sema

namespace llvm {
    template <>
    struct DenseMapInfo<pepper::sema::TypeName> {
        static inline pepper::sema::TypeName getEmptyKey() {
            return pepper::sema::TypeName{"__EMPTY"};
        }

        static inline pepper::sema::TypeName getTombstoneKey() {
            return pepper::sema::TypeName{"__TOMBSTONE"};
        }

        static unsigned getHashValue(const pepper::sema::TypeName& Val) {
            return hash_value(Val.to_string());
        }

        static bool isEqual(const pepper::sema::TypeName& lhs, const pepper::sema::TypeName& rhs) {
            return lhs == rhs;
        }
    };
} // namespace llvm
