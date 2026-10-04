## What operators mean for typing: `BinaryOp::op_name`, `is_comparison`,
## `is_overflow_test`, and the result types of `WeakOp` and `SimdOp`, from
## `model.rs`, in Pepper.

import [BinaryOp, SimdOp, TypeName, WeakOp] from "model";
import [WEAK] from "type_name";

## Returns the operator's name for method overload lookup: `+` for `+`,
## `+=` for `+=`; empty for the operators no method stands behind.
##
## @param op the operator
## @returns its name
export op_name(op: BinaryOp): String {
    match (op) {
        Add => {
            return "+";
        }
        Sub => {
            return "-";
        }
        Mul => {
            return "*";
        }
        Div => {
            return "/";
        }
        Mod => {
            return "%";
        }
        Pow => {
            return "**";
        }
        Equal => {
            return "==";
        }
        NotEqual => {
            return "!=";
        }
        Less => {
            return "<";
        }
        LessEqual => {
            return "<=";
        }
        Greater => {
            return ">";
        }
        GreaterEqual => {
            return ">=";
        }
        LShift => {
            return "<<";
        }
        RShift => {
            return ">>";
        }
        BitAnd => {
            return "&";
        }
        BitOr => {
            return "|";
        }
        BitXor => {
            return "^";
        }
        LogicalAnd => {
            return "&&";
        }
        LogicalOr => {
            return "||";
        }
        AddAssign => {
            return "+=";
        }
        SubAssign => {
            return "-=";
        }
        MulAssign => {
            return "*=";
        }
        DivAssign => {
            return "/=";
        }
        ModAssign => {
            return "%=";
        }
        LShiftAssign => {
            return "<<=";
        }
        RShiftAssign => {
            return ">>=";
        }
        BitAndAssign => {
            return "&=";
        }
        BitOrAssign => {
            return "|=";
        }
        BitXorAssign => {
            return "^=";
        }
        else => {
            return "";
        }
    }
}

## Returns whether `op` compares, its result a `bool`.
##
## @param op the operator
## @returns true for `==`, `!=`, `<`, `<=`, `>`, `>=`, `===`, `!==`
export is_comparison(op: BinaryOp): bool {
    match (op) {
        Identical, NotIdentical, Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns whether `op` tests an arithmetic operation for overflow.
##
## @param op the operator
## @returns true for the `*Overflows` operators
export is_overflow_test(op: BinaryOp): bool {
    match (op) {
        AddOverflows, SubOverflows, MulOverflows => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns the type of a weak-reference operation on `target`.
##
## @param op the operation
## @param target the referenced type
## @returns the result type
export weak_result(op: WeakOp, target: TypeName): TypeName {
    match (op) {
        From => {
            var args = Array<TypeName>();
            args.append(target);
            return TypeName.with_args(WEAK, args);
        }
        Upgrade => {
            return target;
        }
        else => {
            return TypeName.boolean();
        }
    }
}

## Returns the type of a vector operation on vector type `ty`.
##
## @param op the operation
## @param ty the vector type
## @returns the result type
export simd_result(op: SimdOp, ty: TypeName): TypeName {
    match (op) {
        Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual => {
            var mask = ty.copy();
            if (mask.sub_types.count > 0) {
                mask.sub_types[0] = TypeName.boolean();
            }
            return mask;
        }
        Extract, Sum, ReduceMinimum, ReduceMaximum => {
            return ty.sub_types.count > 0 ? ty.sub_types[0] : TypeName.named("int");
        }
        Any, All, IsSigned => {
            return TypeName.boolean();
        }
        ToBits => {
            return TypeName.named("ulong");
        }
        Store, StoreAligned => {
            return TypeName.named("void");
        }
        Lanes, LaneBits => {
            return TypeName.named("int");
        }
        else => {
            return ty;
        }
    }
}
