
#pragma once

#include "Core/Ident.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::ast {

    struct TypeName {
        enum TypeFlags {
            Scalar = 0,
            Array = 1,
            Function = 2,
        } Flags;

        Ident Name;
        std::vector<TypeName> SubTypes;

        TypeName(const Ident& name = {}, const Vector<TypeName, 0>& types = {}, TypeFlags flags = Scalar)
            : Flags(flags)
            , Name(name)
            , SubTypes(types.begin(), types.end()) {}

        TypeName(const TypeName&) = default;
        TypeName(TypeName&&) = default;
        TypeName& operator=(const TypeName&) = default;

        bool empty() const {
            return Name.empty() && SubTypes.empty();
        }

        operator std::string() const {
            return toString();
        }

        bool operator==(const TypeName& rhs) const {
            return Flags == rhs.Flags && Name == rhs.Name && SubTypes == rhs.SubTypes;
        }

        bool operator!=(const TypeName& rhs) const {
            return !(*this == rhs);
        }

        bool isScalar() const {
            return Flags == Scalar;
        }

        bool isArray() const {
            return Flags == Array;
        }

        bool isFunction() const {
            return Flags == Function;
        }

        bool isGeneric() const {
            return (Flags != Array && !SubTypes.empty());
        }

        bool isStruct() const;
        bool isIntegral() const;
        bool isPointer() const;

        const TypeName& elementType() const {
            assert(Flags == Array);
            assert(SubTypes.empty());
            return *this;
        }

        std::string toString() const;

        static TypeName MakeArray(const Ident& arrayTypeName, const TypeName& elementType) {
            return {arrayTypeName, {elementType}, Array};
        }

        static TypeName MakeStruct(const Ident& structTypeName, const Vector<TypeName>& subTypes = {}) {
            return {structTypeName, subTypes};
        }

        static TypeName MakeFunction(const Ident& name, const Vector<TypeName>& genericArgs = {}) {
            return {name, genericArgs, Function};
        }

        static const TypeName& Widest(const TypeName& lhs, const TypeName& rhs);

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
} // namespace pepper::ast

namespace llvm {
    template <>
    struct DenseMapInfo<pepper::ast::TypeName> {
        static inline pepper::ast::TypeName getEmptyKey() {
            return pepper::ast::TypeName{"__EMPTY"};
        }

        static inline pepper::ast::TypeName getTombstoneKey() {
            return pepper::ast::TypeName{"__TOMBSTONE"};
        }

        static unsigned getHashValue(const pepper::ast::TypeName& Val) {
            return hash_value(Val.toString());
        }

        static bool isEqual(const pepper::ast::TypeName& LHS, const pepper::ast::TypeName& RHS) {
            return LHS == RHS;
        }
    };
} // namespace llvm
