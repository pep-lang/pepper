
#include "AST/TypeName.h"

#include "Core/Exceptions.h"
#include "Core/Query.h"

namespace pepper::ast {
    const TypeName TypeName::Empty;
    const TypeName TypeName::Void = TypeName{"void"};
    const TypeName TypeName::Auto = TypeName{"__auto"};
    const TypeName TypeName::Bool = TypeName{"bool"};
    const TypeName TypeName::VoidPtr = TypeName{"void*"};
    const TypeName TypeName::Int8 = TypeName{"i8"};
    const TypeName TypeName::UInt8 = TypeName{"u8"};
    const TypeName TypeName::Int32 = TypeName{"i32"};
    const TypeName TypeName::UInt32 = TypeName{"u32"};
    const TypeName TypeName::Int64 = TypeName{"i64"};
    const TypeName TypeName::UInt64 = TypeName{"u64"};
    const TypeName TypeName::Double = TypeName{"f64"};
    const TypeName TypeName::Float = TypeName{"f32"};

    // clang-format off
    llvm::StringSet<> TypeName::IntegralTypes = {
        Void.Name,
        Auto.Name,
        Bool.Name,

        VoidPtr.Name,
        Int8.Name,
        "char",
        UInt8.Name,
        "byte",
        Int32.Name,
        "int",
        UInt32.Name,
        "uint",
        Int64.Name,
        "long",
        UInt64.Name,
        "ulong",
        Double.Name,
        "double",
        Float.Name,
        "float",
    };

    // clang-format on

    const TypeName& TypeName::Widest(const TypeName& lhs, const TypeName& rhs) {
        struct NumericTypeName {
            const TypeName* Name;
            const unsigned Width = -1;
            const bool isSigned = true;
            const bool isFloat = false;
        };

        static llvm::StringMap<NumericTypeName> NumericTypes = {
            {"i1", {&TypeName::Bool, 1}},
            {"bool", {&TypeName::Bool, 1}},
            {"i8", {&TypeName::Int8, 8}},
            {"char", {&TypeName::Int8, 8}},
            {"u8", {&TypeName::UInt8, 8, false}},
            {"byte", {&TypeName::UInt8, 8, false}},
            {"i32", {&TypeName::Int32, 32}},
            {"int", {&TypeName::Int32, 32}},
            {"u32", {&TypeName::UInt32, 32, false}},
            {"uint", {&TypeName::UInt32, 32, false}},
            {"i64", {&TypeName::Int64, 64}},
            {"long", {&TypeName::Int64, 64}},
            {"u64", {&TypeName::UInt64, 64, false}},
            {"ulong", {&TypeName::UInt64, 64, false}},
            {"f32", {&TypeName::Float, 32, true, true}},
            {"float", {&TypeName::Float, 32, true, true}},
            {"f64", {&TypeName::Double, 64, true, true}},
            {"double", {&TypeName::Double, 64, true, true}},
        };

        assert(!lhs.isGeneric() && !rhs.isGeneric());

        const auto lhsName = lhs.Name;
        const auto rhsName = rhs.Name;

        const bool lhsNumeric = NumericTypes.find(lhsName) != NumericTypes.end();
        const bool rhsNumeric = NumericTypes.find(rhsName) != NumericTypes.end();
        assert(lhsNumeric && rhsNumeric);

        const auto& lhsType = NumericTypes.lookup(lhsName);
        const auto& rhsType = NumericTypes.lookup(rhsName);

        const auto width = std::max(lhsType.Width, rhsType.Width);
        if (lhsType.isFloat || rhsType.isFloat)
            return width > 32 ? TypeName::Double : TypeName::Float;
        if (!lhsType.isSigned && !rhsType.isSigned) {
            if (width > 32)
                return TypeName::UInt64;
            if (width > 8)
                return TypeName::UInt32;
            return TypeName::UInt8;
        }
        if (width > 32)
            return TypeName::Int64;
        if (width > 8)
            return TypeName::Int32;
        return TypeName::Int8;

        throw InternalCompilerError(
            "Incomparable types encountered while computing width: {0}, {1}", lhs.toString(), rhs.toString());
    }

    bool TypeName::isPointer() const {
        return isScalar() && Name.ends_with('*');
    }

    bool TypeName::isIntegral() const {
        return isScalar() && IntegralTypes.contains(Name);
    }

    bool TypeName::isStruct() const {
        return (isScalar() && !isIntegral());
    }

    std::string TypeName::toString() const {
        std::string genericTypes;
        if (isGeneric()) {
            Vector<std::string> genericStrings =
                Query(SubTypes).select<std::string>([](auto& a) { return a.toString(); });
            genericTypes = "<" + llvm::join(genericStrings.begin(), genericStrings.end(), ", ") + ">";
        }
        std::string ptr = isArray() ? "*" : "";
        return Name + genericTypes + ptr;
    }
} // namespace pepper::ast
