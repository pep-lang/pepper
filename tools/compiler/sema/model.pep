## The sema model: `crates/pepper-sema/src/model.rs` and `type_name.rs` in
## Pepper, the tree the builder makes of the linked program and the passes
## rewrite. Each Rust enum variant with named fields holds a struct of its
## own (`SymbolRefExpression` for `Expression::SymbolRef`), so a pass can
## change a node's fields in place. Each type's `to_json()` writes what
## serde writes for the Rust type.

import compiler.ast;
import json;
import [JsonValue] from json;
import [Fingerprint] from "fingerprint";
import [Loc] from "loc";

## `BinaryOp` in `model.rs`.
export enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    Identical,
    NotIdentical,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    LShift,
    RShift,
    BitAnd,
    BitOr,
    BitXor,
    LogicalAnd,
    LogicalOr,
    Assign,
    AddAssign,
    SubAssign,
    MulAssign,
    DivAssign,
    ModAssign,
    LShiftAssign,
    RShiftAssign,
    BitAndAssign,
    BitOrAssign,
    BitXorAssign,
    WrappingAdd,
    WrappingSub,
    WrappingMul,
    AddOverflows,
    SubOverflows,
    MulOverflows,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Add => {
                into.add(0);
            }
            Sub => {
                into.add(1);
            }
            Mul => {
                into.add(2);
            }
            Div => {
                into.add(3);
            }
            Mod => {
                into.add(4);
            }
            Pow => {
                into.add(5);
            }
            Identical => {
                into.add(6);
            }
            NotIdentical => {
                into.add(7);
            }
            Equal => {
                into.add(8);
            }
            NotEqual => {
                into.add(9);
            }
            Less => {
                into.add(10);
            }
            LessEqual => {
                into.add(11);
            }
            Greater => {
                into.add(12);
            }
            GreaterEqual => {
                into.add(13);
            }
            LShift => {
                into.add(14);
            }
            RShift => {
                into.add(15);
            }
            BitAnd => {
                into.add(16);
            }
            BitOr => {
                into.add(17);
            }
            BitXor => {
                into.add(18);
            }
            LogicalAnd => {
                into.add(19);
            }
            LogicalOr => {
                into.add(20);
            }
            Assign => {
                into.add(21);
            }
            AddAssign => {
                into.add(22);
            }
            SubAssign => {
                into.add(23);
            }
            MulAssign => {
                into.add(24);
            }
            DivAssign => {
                into.add(25);
            }
            ModAssign => {
                into.add(26);
            }
            LShiftAssign => {
                into.add(27);
            }
            RShiftAssign => {
                into.add(28);
            }
            BitAndAssign => {
                into.add(29);
            }
            BitOrAssign => {
                into.add(30);
            }
            BitXorAssign => {
                into.add(31);
            }
            WrappingAdd => {
                into.add(32);
            }
            WrappingSub => {
                into.add(33);
            }
            WrappingMul => {
                into.add(34);
            }
            AddOverflows => {
                into.add(35);
            }
            SubOverflows => {
                into.add(36);
            }
            MulOverflows => {
                into.add(37);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Add => {
                return JsonValue.String("Add");
            }
            Sub => {
                return JsonValue.String("Sub");
            }
            Mul => {
                return JsonValue.String("Mul");
            }
            Div => {
                return JsonValue.String("Div");
            }
            Mod => {
                return JsonValue.String("Mod");
            }
            Pow => {
                return JsonValue.String("Pow");
            }
            Identical => {
                return JsonValue.String("Identical");
            }
            NotIdentical => {
                return JsonValue.String("NotIdentical");
            }
            Equal => {
                return JsonValue.String("Equal");
            }
            NotEqual => {
                return JsonValue.String("NotEqual");
            }
            Less => {
                return JsonValue.String("Less");
            }
            LessEqual => {
                return JsonValue.String("LessEqual");
            }
            Greater => {
                return JsonValue.String("Greater");
            }
            GreaterEqual => {
                return JsonValue.String("GreaterEqual");
            }
            LShift => {
                return JsonValue.String("LShift");
            }
            RShift => {
                return JsonValue.String("RShift");
            }
            BitAnd => {
                return JsonValue.String("BitAnd");
            }
            BitOr => {
                return JsonValue.String("BitOr");
            }
            BitXor => {
                return JsonValue.String("BitXor");
            }
            LogicalAnd => {
                return JsonValue.String("LogicalAnd");
            }
            LogicalOr => {
                return JsonValue.String("LogicalOr");
            }
            Assign => {
                return JsonValue.String("Assign");
            }
            AddAssign => {
                return JsonValue.String("AddAssign");
            }
            SubAssign => {
                return JsonValue.String("SubAssign");
            }
            MulAssign => {
                return JsonValue.String("MulAssign");
            }
            DivAssign => {
                return JsonValue.String("DivAssign");
            }
            ModAssign => {
                return JsonValue.String("ModAssign");
            }
            LShiftAssign => {
                return JsonValue.String("LShiftAssign");
            }
            RShiftAssign => {
                return JsonValue.String("RShiftAssign");
            }
            BitAndAssign => {
                return JsonValue.String("BitAndAssign");
            }
            BitOrAssign => {
                return JsonValue.String("BitOrAssign");
            }
            BitXorAssign => {
                return JsonValue.String("BitXorAssign");
            }
            WrappingAdd => {
                return JsonValue.String("WrappingAdd");
            }
            WrappingSub => {
                return JsonValue.String("WrappingSub");
            }
            WrappingMul => {
                return JsonValue.String("WrappingMul");
            }
            AddOverflows => {
                return JsonValue.String("AddOverflows");
            }
            SubOverflows => {
                return JsonValue.String("SubOverflows");
            }
            MulOverflows => {
                return JsonValue.String("MulOverflows");
            }
        }
    }
}

## `UnaryOp` in `model.rs`.
export enum UnaryOp {
    Neg,
    Pos,
    PreInc,
    PostInc,
    PreDec,
    PostDec,
    LogicalNot,
    BitNot,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Neg => {
                into.add(0);
            }
            Pos => {
                into.add(1);
            }
            PreInc => {
                into.add(2);
            }
            PostInc => {
                into.add(3);
            }
            PreDec => {
                into.add(4);
            }
            PostDec => {
                into.add(5);
            }
            LogicalNot => {
                into.add(6);
            }
            BitNot => {
                into.add(7);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Neg => {
                return JsonValue.String("Neg");
            }
            Pos => {
                return JsonValue.String("Pos");
            }
            PreInc => {
                return JsonValue.String("PreInc");
            }
            PostInc => {
                return JsonValue.String("PostInc");
            }
            PreDec => {
                return JsonValue.String("PreDec");
            }
            PostDec => {
                return JsonValue.String("PostDec");
            }
            LogicalNot => {
                return JsonValue.String("LogicalNot");
            }
            BitNot => {
                return JsonValue.String("BitNot");
            }
        }
    }
}

## `Kind` in `model.rs`.
export enum Kind {
    Variable,
    Field,
    Param,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Variable => {
                into.add(0);
            }
            Field => {
                into.add(1);
            }
            Param => {
                into.add(2);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Variable => {
                return JsonValue.String("Variable");
            }
            Field => {
                return JsonValue.String("Field");
            }
            Param => {
                return JsonValue.String("Param");
            }
        }
    }
}

## `AtomicFetchOp` in `model.rs`.
export enum AtomicFetchOp {
    Add,
    Sub,
    And,
    Or,
    Xor,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Add => {
                into.add(0);
            }
            Sub => {
                into.add(1);
            }
            And => {
                into.add(2);
            }
            Or => {
                into.add(3);
            }
            Xor => {
                into.add(4);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Add => {
                return JsonValue.String("Add");
            }
            Sub => {
                return JsonValue.String("Sub");
            }
            And => {
                return JsonValue.String("And");
            }
            Or => {
                return JsonValue.String("Or");
            }
            Xor => {
                return JsonValue.String("Xor");
            }
        }
    }
}

## `SimdOp` in `model.rs`.
export enum SimdOp {
    Splat,
    Add,
    Subtract,
    Multiply,
    Divide,
    Remainder,
    And,
    Or,
    Xor,
    ShiftLeft,
    ShiftRight,
    Negate,
    Not,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Select,
    Minimum,
    Maximum,
    Abs,
    RotateLeft,
    RotateRight,
    SquareRoot,
    Floor,
    Ceiling,
    Sum,
    ReduceMinimum,
    ReduceMaximum,
    Any,
    All,
    ToBits,
    Extract,
    Insert,
    Shuffle,
    Reverse,
    InterleaveLow,
    InterleaveHigh,
    Load,
    LoadAligned,
    Store,
    StoreAligned,
    Convert,
    Reinterpret,
    Lanes,
    LaneBits,
    IsSigned,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Splat => {
                into.add(0);
            }
            Add => {
                into.add(1);
            }
            Subtract => {
                into.add(2);
            }
            Multiply => {
                into.add(3);
            }
            Divide => {
                into.add(4);
            }
            Remainder => {
                into.add(5);
            }
            And => {
                into.add(6);
            }
            Or => {
                into.add(7);
            }
            Xor => {
                into.add(8);
            }
            ShiftLeft => {
                into.add(9);
            }
            ShiftRight => {
                into.add(10);
            }
            Negate => {
                into.add(11);
            }
            Not => {
                into.add(12);
            }
            Equal => {
                into.add(13);
            }
            NotEqual => {
                into.add(14);
            }
            Less => {
                into.add(15);
            }
            LessEqual => {
                into.add(16);
            }
            Greater => {
                into.add(17);
            }
            GreaterEqual => {
                into.add(18);
            }
            Select => {
                into.add(19);
            }
            Minimum => {
                into.add(20);
            }
            Maximum => {
                into.add(21);
            }
            Abs => {
                into.add(22);
            }
            RotateLeft => {
                into.add(23);
            }
            RotateRight => {
                into.add(24);
            }
            SquareRoot => {
                into.add(25);
            }
            Floor => {
                into.add(26);
            }
            Ceiling => {
                into.add(27);
            }
            Sum => {
                into.add(28);
            }
            ReduceMinimum => {
                into.add(29);
            }
            ReduceMaximum => {
                into.add(30);
            }
            Any => {
                into.add(31);
            }
            All => {
                into.add(32);
            }
            ToBits => {
                into.add(33);
            }
            Extract => {
                into.add(34);
            }
            Insert => {
                into.add(35);
            }
            Shuffle => {
                into.add(36);
            }
            Reverse => {
                into.add(37);
            }
            InterleaveLow => {
                into.add(38);
            }
            InterleaveHigh => {
                into.add(39);
            }
            Load => {
                into.add(40);
            }
            LoadAligned => {
                into.add(41);
            }
            Store => {
                into.add(42);
            }
            StoreAligned => {
                into.add(43);
            }
            Convert => {
                into.add(44);
            }
            Reinterpret => {
                into.add(45);
            }
            Lanes => {
                into.add(46);
            }
            LaneBits => {
                into.add(47);
            }
            IsSigned => {
                into.add(48);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Splat => {
                return JsonValue.String("Splat");
            }
            Add => {
                return JsonValue.String("Add");
            }
            Subtract => {
                return JsonValue.String("Subtract");
            }
            Multiply => {
                return JsonValue.String("Multiply");
            }
            Divide => {
                return JsonValue.String("Divide");
            }
            Remainder => {
                return JsonValue.String("Remainder");
            }
            And => {
                return JsonValue.String("And");
            }
            Or => {
                return JsonValue.String("Or");
            }
            Xor => {
                return JsonValue.String("Xor");
            }
            ShiftLeft => {
                return JsonValue.String("ShiftLeft");
            }
            ShiftRight => {
                return JsonValue.String("ShiftRight");
            }
            Negate => {
                return JsonValue.String("Negate");
            }
            Not => {
                return JsonValue.String("Not");
            }
            Equal => {
                return JsonValue.String("Equal");
            }
            NotEqual => {
                return JsonValue.String("NotEqual");
            }
            Less => {
                return JsonValue.String("Less");
            }
            LessEqual => {
                return JsonValue.String("LessEqual");
            }
            Greater => {
                return JsonValue.String("Greater");
            }
            GreaterEqual => {
                return JsonValue.String("GreaterEqual");
            }
            Select => {
                return JsonValue.String("Select");
            }
            Minimum => {
                return JsonValue.String("Minimum");
            }
            Maximum => {
                return JsonValue.String("Maximum");
            }
            Abs => {
                return JsonValue.String("Abs");
            }
            RotateLeft => {
                return JsonValue.String("RotateLeft");
            }
            RotateRight => {
                return JsonValue.String("RotateRight");
            }
            SquareRoot => {
                return JsonValue.String("SquareRoot");
            }
            Floor => {
                return JsonValue.String("Floor");
            }
            Ceiling => {
                return JsonValue.String("Ceiling");
            }
            Sum => {
                return JsonValue.String("Sum");
            }
            ReduceMinimum => {
                return JsonValue.String("ReduceMinimum");
            }
            ReduceMaximum => {
                return JsonValue.String("ReduceMaximum");
            }
            Any => {
                return JsonValue.String("Any");
            }
            All => {
                return JsonValue.String("All");
            }
            ToBits => {
                return JsonValue.String("ToBits");
            }
            Extract => {
                return JsonValue.String("Extract");
            }
            Insert => {
                return JsonValue.String("Insert");
            }
            Shuffle => {
                return JsonValue.String("Shuffle");
            }
            Reverse => {
                return JsonValue.String("Reverse");
            }
            InterleaveLow => {
                return JsonValue.String("InterleaveLow");
            }
            InterleaveHigh => {
                return JsonValue.String("InterleaveHigh");
            }
            Load => {
                return JsonValue.String("Load");
            }
            LoadAligned => {
                return JsonValue.String("LoadAligned");
            }
            Store => {
                return JsonValue.String("Store");
            }
            StoreAligned => {
                return JsonValue.String("StoreAligned");
            }
            Convert => {
                return JsonValue.String("Convert");
            }
            Reinterpret => {
                return JsonValue.String("Reinterpret");
            }
            Lanes => {
                return JsonValue.String("Lanes");
            }
            LaneBits => {
                return JsonValue.String("LaneBits");
            }
            IsSigned => {
                return JsonValue.String("IsSigned");
            }
        }
    }
}

## `CastKind` in `model.rs`.
export enum CastKind {
    Static,
    Unsafe,
    Synthesized,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Static => {
                into.add(0);
            }
            Unsafe => {
                into.add(1);
            }
            Synthesized => {
                into.add(2);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Static => {
                return JsonValue.String("Static");
            }
            Unsafe => {
                return JsonValue.String("Unsafe");
            }
            Synthesized => {
                return JsonValue.String("Synthesized");
            }
        }
    }
}

## `Expression` in `model.rs`.
export enum Expression {
    SymbolRef(node: SymbolRefExpression),
    ThisRef,
    MemberRef(node: MemberRefExpression),
    BoolLiteral(value: bool),
    IntLiteral(value: long),
    FloatLiteral(value: double),
    StringLiteral(node: StringLiteralExpression),
    PointerLiteral,
    Binary(node: BinaryExpression),
    Unary(node: UnaryExpression),
    Cast(node: CastExpression),
    Ternary(node: TernaryExpression),
    Index(node: IndexExpression),
    ArrayIndex(node: ArrayIndexExpression),
    SizeOf(value: TypeName),
    IsPod(value: TypeName),
    Default(value: TypeName),
    Allocate(value: TypeName),
    RefCount(v0: TypeName, v1: Expression),
    Address(v0: TypeName, v1: Expression),
    AtomicLoad(v0: TypeName, v1: Expression),
    AtomicStore(v0: TypeName, v1: Expression, v2: Expression),
    ConstructAt(v0: Expression, v1: Expression),
    AtomicCmpXchg(v0: TypeName, v1: Expression, v2: Expression, v3: Expression),
    AtomicFetch(v0: AtomicFetchOp, v1: TypeName, v2: Expression, v3: Expression),
    Simd(node: SimdExpression),
    Weak(v0: WeakOp, v1: TypeName, v2: Expression),
    CountStep(node: CountStepExpression),
    FunctionPointer(node: FunctionPointerExpression),
    FunctionCall(node: FunctionCallExpression),
    NamedArgument(node: NamedArgumentExpression),
    DefaultArgument(node: DefaultArgumentExpression),
    MethodCall(node: MethodCallExpression),
    FunctionRef(node: FunctionRefExpression),
    Invoke(node: InvokeExpression),
    ClosureLiteral(value: ClosureLiteral),
    MakeClosure(node: MakeClosureExpression),
    MethodAddress(value: String),
    CallPointer(node: CallPointerExpression),
    ForIterator(value: Expression),
    WithEntered(value: Expression),
    Move(node: MoveExpression),
    Destructure(node: DestructureExpression),
    MatchArm(value: MatchArmTest),
    CaseValue(value: CaseValue),
    StaticCase(node: StaticCaseExpression),
    StaticString(node: StaticStringExpression),
    WithSubject(value: WithSubject),
    Subject(node: SubjectExpression),
    NoMatch,
    ToTrait(node: ToTraitExpression),
    FromTrait(node: FromTraitExpression),
    StaticValue(value: StaticValue),
    StaticMember(value: StaticMember),

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            SymbolRef(node) => {
                into.add(0);
                node.fingerprint(into);
            }
            ThisRef => {
                into.add(1);
            }
            MemberRef(node) => {
                into.add(2);
                node.fingerprint(into);
            }
            BoolLiteral(value) => {
                into.add(3);
                into.add(value ? 1 : 0);
            }
            IntLiteral(value) => {
                into.add(4);
                into.add(value as ulong);
            }
            FloatLiteral(value) => {
                into.add(5);
                into.add_text($"{value}");
            }
            StringLiteral(node) => {
                into.add(6);
                node.fingerprint(into);
            }
            PointerLiteral => {
                into.add(7);
            }
            Binary(node) => {
                into.add(8);
                node.fingerprint(into);
            }
            Unary(node) => {
                into.add(9);
                node.fingerprint(into);
            }
            Cast(node) => {
                into.add(10);
                node.fingerprint(into);
            }
            Ternary(node) => {
                into.add(11);
                node.fingerprint(into);
            }
            Index(node) => {
                into.add(12);
                node.fingerprint(into);
            }
            ArrayIndex(node) => {
                into.add(13);
                node.fingerprint(into);
            }
            SizeOf(value) => {
                into.add(14);
                value.fingerprint(into);
            }
            IsPod(value) => {
                into.add(15);
                value.fingerprint(into);
            }
            Default(value) => {
                into.add(16);
                value.fingerprint(into);
            }
            Allocate(value) => {
                into.add(17);
                value.fingerprint(into);
            }
            RefCount(v0, v1) => {
                into.add(18);
                v0.fingerprint(into);
                v1.fingerprint(into);
            }
            Address(v0, v1) => {
                into.add(19);
                v0.fingerprint(into);
                v1.fingerprint(into);
            }
            AtomicLoad(v0, v1) => {
                into.add(20);
                v0.fingerprint(into);
                v1.fingerprint(into);
            }
            AtomicStore(v0, v1, v2) => {
                into.add(21);
                v0.fingerprint(into);
                v1.fingerprint(into);
                v2.fingerprint(into);
            }
            ConstructAt(v0, v1) => {
                into.add(22);
                v0.fingerprint(into);
                v1.fingerprint(into);
            }
            AtomicCmpXchg(v0, v1, v2, v3) => {
                into.add(23);
                v0.fingerprint(into);
                v1.fingerprint(into);
                v2.fingerprint(into);
                v3.fingerprint(into);
            }
            AtomicFetch(v0, v1, v2, v3) => {
                into.add(24);
                v0.fingerprint(into);
                v1.fingerprint(into);
                v2.fingerprint(into);
                v3.fingerprint(into);
            }
            Simd(node) => {
                into.add(25);
                node.fingerprint(into);
            }
            Weak(v0, v1, v2) => {
                into.add(26);
                v0.fingerprint(into);
                v1.fingerprint(into);
                v2.fingerprint(into);
            }
            CountStep(node) => {
                into.add(27);
                node.fingerprint(into);
            }
            FunctionPointer(node) => {
                into.add(28);
                node.fingerprint(into);
            }
            FunctionCall(node) => {
                into.add(29);
                node.fingerprint(into);
            }
            NamedArgument(node) => {
                into.add(30);
                node.fingerprint(into);
            }
            DefaultArgument(node) => {
                into.add(31);
                node.fingerprint(into);
            }
            MethodCall(node) => {
                into.add(32);
                node.fingerprint(into);
            }
            FunctionRef(node) => {
                into.add(33);
                node.fingerprint(into);
            }
            Invoke(node) => {
                into.add(34);
                node.fingerprint(into);
            }
            ClosureLiteral(value) => {
                into.add(35);
                value.fingerprint(into);
            }
            MakeClosure(node) => {
                into.add(36);
                node.fingerprint(into);
            }
            MethodAddress(value) => {
                into.add(37);
                into.add_text(value);
            }
            CallPointer(node) => {
                into.add(38);
                node.fingerprint(into);
            }
            ForIterator(value) => {
                into.add(39);
                value.fingerprint(into);
            }
            WithEntered(value) => {
                into.add(40);
                value.fingerprint(into);
            }
            Move(node) => {
                into.add(41);
                node.fingerprint(into);
            }
            Destructure(node) => {
                into.add(42);
                node.fingerprint(into);
            }
            MatchArm(value) => {
                into.add(43);
                value.fingerprint(into);
            }
            CaseValue(value) => {
                into.add(44);
                value.fingerprint(into);
            }
            StaticCase(node) => {
                into.add(45);
                node.fingerprint(into);
            }
            StaticString(node) => {
                into.add(46);
                node.fingerprint(into);
            }
            WithSubject(value) => {
                into.add(47);
                value.fingerprint(into);
            }
            Subject(node) => {
                into.add(48);
                node.fingerprint(into);
            }
            NoMatch => {
                into.add(49);
            }
            ToTrait(node) => {
                into.add(50);
                node.fingerprint(into);
            }
            FromTrait(node) => {
                into.add(51);
                node.fingerprint(into);
            }
            StaticValue(value) => {
                into.add(52);
                value.fingerprint(into);
            }
            StaticMember(value) => {
                into.add(53);
                value.fingerprint(into);
            }
        }
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Expression {
        match (this) {
            SymbolRef(node) => {
                return Expression.SymbolRef(node.copy());
            }
            ThisRef => {
                return this;
            }
            MemberRef(node) => {
                return Expression.MemberRef(node.copy());
            }
            BoolLiteral(value) => {
                return Expression.BoolLiteral(value);
            }
            IntLiteral(value) => {
                return Expression.IntLiteral(value);
            }
            FloatLiteral(value) => {
                return Expression.FloatLiteral(value);
            }
            StringLiteral(node) => {
                return Expression.StringLiteral(node.copy());
            }
            PointerLiteral => {
                return this;
            }
            Binary(node) => {
                return Expression.Binary(node.copy());
            }
            Unary(node) => {
                return Expression.Unary(node.copy());
            }
            Cast(node) => {
                return Expression.Cast(node.copy());
            }
            Ternary(node) => {
                return Expression.Ternary(node.copy());
            }
            Index(node) => {
                return Expression.Index(node.copy());
            }
            ArrayIndex(node) => {
                return Expression.ArrayIndex(node.copy());
            }
            SizeOf(value) => {
                return Expression.SizeOf(value.copy());
            }
            IsPod(value) => {
                return Expression.IsPod(value.copy());
            }
            Default(value) => {
                return Expression.Default(value.copy());
            }
            Allocate(value) => {
                return Expression.Allocate(value.copy());
            }
            RefCount(v0, v1) => {
                return Expression.RefCount(v0.copy(), v1.copy());
            }
            Address(v0, v1) => {
                return Expression.Address(v0.copy(), v1.copy());
            }
            AtomicLoad(v0, v1) => {
                return Expression.AtomicLoad(v0.copy(), v1.copy());
            }
            AtomicStore(v0, v1, v2) => {
                return Expression.AtomicStore(v0.copy(), v1.copy(), v2.copy());
            }
            ConstructAt(v0, v1) => {
                return Expression.ConstructAt(v0.copy(), v1.copy());
            }
            AtomicCmpXchg(v0, v1, v2, v3) => {
                return Expression.AtomicCmpXchg(v0.copy(), v1.copy(), v2.copy(), v3.copy());
            }
            AtomicFetch(v0, v1, v2, v3) => {
                return Expression.AtomicFetch(v0, v1.copy(), v2.copy(), v3.copy());
            }
            Simd(node) => {
                return Expression.Simd(node.copy());
            }
            Weak(v0, v1, v2) => {
                return Expression.Weak(v0, v1.copy(), v2.copy());
            }
            CountStep(node) => {
                return Expression.CountStep(node.copy());
            }
            FunctionPointer(node) => {
                return Expression.FunctionPointer(node.copy());
            }
            FunctionCall(node) => {
                return Expression.FunctionCall(node.copy());
            }
            NamedArgument(node) => {
                return Expression.NamedArgument(node.copy());
            }
            DefaultArgument(node) => {
                return Expression.DefaultArgument(node.copy());
            }
            MethodCall(node) => {
                return Expression.MethodCall(node.copy());
            }
            FunctionRef(node) => {
                return Expression.FunctionRef(node.copy());
            }
            Invoke(node) => {
                return Expression.Invoke(node.copy());
            }
            ClosureLiteral(value) => {
                return Expression.ClosureLiteral(value.copy());
            }
            MakeClosure(node) => {
                return Expression.MakeClosure(node.copy());
            }
            MethodAddress(value) => {
                return Expression.MethodAddress(value);
            }
            CallPointer(node) => {
                return Expression.CallPointer(node.copy());
            }
            ForIterator(value) => {
                return Expression.ForIterator(value.copy());
            }
            WithEntered(value) => {
                return Expression.WithEntered(value.copy());
            }
            Move(node) => {
                return Expression.Move(node.copy());
            }
            Destructure(node) => {
                return Expression.Destructure(node.copy());
            }
            MatchArm(value) => {
                return Expression.MatchArm(value.copy());
            }
            CaseValue(value) => {
                return Expression.CaseValue(value.copy());
            }
            StaticCase(node) => {
                return Expression.StaticCase(node.copy());
            }
            StaticString(node) => {
                return Expression.StaticString(node.copy());
            }
            WithSubject(value) => {
                return Expression.WithSubject(value.copy());
            }
            Subject(node) => {
                return Expression.Subject(node.copy());
            }
            NoMatch => {
                return this;
            }
            ToTrait(node) => {
                return Expression.ToTrait(node.copy());
            }
            FromTrait(node) => {
                return Expression.FromTrait(node.copy());
            }
            StaticValue(value) => {
                return Expression.StaticValue(value.copy());
            }
            StaticMember(value) => {
                return Expression.StaticMember(value.copy());
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            SymbolRef(node) => {
                return _tagged("SymbolRef", node.to_json());
            }
            ThisRef => {
                return JsonValue.String("ThisRef");
            }
            MemberRef(node) => {
                return _tagged("MemberRef", node.to_json());
            }
            BoolLiteral(value) => {
                return _tagged("BoolLiteral", JsonValue.Bool(value));
            }
            IntLiteral(value) => {
                return _tagged("IntLiteral", JsonValue.Integer(value as long));
            }
            FloatLiteral(value) => {
                return _tagged("FloatLiteral", JsonValue.Number(value));
            }
            StringLiteral(node) => {
                return _tagged("StringLiteral", node.to_json());
            }
            PointerLiteral => {
                return JsonValue.String("PointerLiteral");
            }
            Binary(node) => {
                return _tagged("Binary", node.to_json());
            }
            Unary(node) => {
                return _tagged("Unary", node.to_json());
            }
            Cast(node) => {
                return _tagged("Cast", node.to_json());
            }
            Ternary(node) => {
                return _tagged("Ternary", node.to_json());
            }
            Index(node) => {
                return _tagged("Index", node.to_json());
            }
            ArrayIndex(node) => {
                return _tagged("ArrayIndex", node.to_json());
            }
            SizeOf(value) => {
                return _tagged("SizeOf", value.to_json());
            }
            IsPod(value) => {
                return _tagged("IsPod", value.to_json());
            }
            Default(value) => {
                return _tagged("Default", value.to_json());
            }
            Allocate(value) => {
                return _tagged("Allocate", value.to_json());
            }
            RefCount(v0, v1) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                return _tagged("RefCount", items);
            }
            Address(v0, v1) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                return _tagged("Address", items);
            }
            AtomicLoad(v0, v1) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                return _tagged("AtomicLoad", items);
            }
            AtomicStore(v0, v1, v2) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                items.append(v2.to_json());
                return _tagged("AtomicStore", items);
            }
            ConstructAt(v0, v1) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                return _tagged("ConstructAt", items);
            }
            AtomicCmpXchg(v0, v1, v2, v3) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                items.append(v2.to_json());
                items.append(v3.to_json());
                return _tagged("AtomicCmpXchg", items);
            }
            AtomicFetch(v0, v1, v2, v3) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                items.append(v2.to_json());
                items.append(v3.to_json());
                return _tagged("AtomicFetch", items);
            }
            Simd(node) => {
                return _tagged("Simd", node.to_json());
            }
            Weak(v0, v1, v2) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                items.append(v2.to_json());
                return _tagged("Weak", items);
            }
            CountStep(node) => {
                return _tagged("CountStep", node.to_json());
            }
            FunctionPointer(node) => {
                return _tagged("FunctionPointer", node.to_json());
            }
            FunctionCall(node) => {
                return _tagged("FunctionCall", node.to_json());
            }
            NamedArgument(node) => {
                return _tagged("NamedArgument", node.to_json());
            }
            DefaultArgument(node) => {
                return _tagged("DefaultArgument", node.to_json());
            }
            MethodCall(node) => {
                return _tagged("MethodCall", node.to_json());
            }
            FunctionRef(node) => {
                return _tagged("FunctionRef", node.to_json());
            }
            Invoke(node) => {
                return _tagged("Invoke", node.to_json());
            }
            ClosureLiteral(value) => {
                return _tagged("ClosureLiteral", value.to_json());
            }
            MakeClosure(node) => {
                return _tagged("MakeClosure", node.to_json());
            }
            MethodAddress(value) => {
                return _tagged("MethodAddress", JsonValue.String(value));
            }
            CallPointer(node) => {
                return _tagged("CallPointer", node.to_json());
            }
            ForIterator(value) => {
                return _tagged("ForIterator", value.to_json());
            }
            WithEntered(value) => {
                return _tagged("WithEntered", value.to_json());
            }
            Move(node) => {
                return _tagged("Move", node.to_json());
            }
            Destructure(node) => {
                return _tagged("Destructure", node.to_json());
            }
            MatchArm(value) => {
                return _tagged("MatchArm", value.to_json());
            }
            CaseValue(value) => {
                return _tagged("CaseValue", value.to_json());
            }
            StaticCase(node) => {
                return _tagged("StaticCase", node.to_json());
            }
            StaticString(node) => {
                return _tagged("StaticString", node.to_json());
            }
            WithSubject(value) => {
                return _tagged("WithSubject", value.to_json());
            }
            Subject(node) => {
                return _tagged("Subject", node.to_json());
            }
            NoMatch => {
                return JsonValue.String("NoMatch");
            }
            ToTrait(node) => {
                return _tagged("ToTrait", node.to_json());
            }
            FromTrait(node) => {
                return _tagged("FromTrait", node.to_json());
            }
            StaticValue(value) => {
                return _tagged("StaticValue", value.to_json());
            }
            StaticMember(value) => {
                return _tagged("StaticMember", value.to_json());
            }
        }
    }
}

## The fields of `Expression::SymbolRef`.
export struct SymbolRefExpression {
    var id: String;
    var ty: TypeName;
    var loc: Loc;

    construct(id: String = "", ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.id = id;
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): SymbolRefExpression {
        return SymbolRefExpression(id = this.id, ty = this.ty.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("SymbolRefExpression");
        into.add_text(this.id);
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = JsonValue.String(this.id);
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::MemberRef`.
export struct MemberRefExpression {
    var lhs: Expression;
    var name: String;
    var loc: Loc;

    construct(lhs: Expression, name: String = "", loc: Loc = Loc()) {
        this.lhs = lhs;
        this.name = name;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MemberRefExpression {
        return MemberRefExpression(lhs = this.lhs.copy(), name = this.name, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MemberRefExpression");
        this.lhs.fingerprint(into);
        into.add_text(this.name);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["lhs"] = this.lhs.to_json();
        out["name"] = JsonValue.String(this.name);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::StringLiteral`.
export struct StringLiteralExpression {
    var value: String;
    var is_raw: bool;
    var loc: Loc;

    construct(value: String = "", is_raw: bool = false, loc: Loc = Loc()) {
        this.value = value;
        this.is_raw = is_raw;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StringLiteralExpression {
        return StringLiteralExpression(value = this.value, is_raw = this.is_raw, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StringLiteralExpression");
        into.add_text(this.value);
        into.add(this.is_raw ? 1 : 0);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = JsonValue.String(this.value);
        out["is_raw"] = JsonValue.Bool(this.is_raw);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Binary`.
export struct BinaryExpression {
    var op: BinaryOp;
    var lhs: Expression;
    var rhs: Expression;
    var loc: Loc;

    construct(lhs: Expression, rhs: Expression, op: BinaryOp = BinaryOp.Add, loc: Loc = Loc()) {
        this.lhs = lhs;
        this.rhs = rhs;
        this.op = op;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): BinaryExpression {
        return BinaryExpression(op = this.op, lhs = this.lhs.copy(), rhs = this.rhs.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("BinaryExpression");
        this.op.fingerprint(into);
        this.lhs.fingerprint(into);
        this.rhs.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["op"] = this.op.to_json();
        out["lhs"] = this.lhs.to_json();
        out["rhs"] = this.rhs.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Unary`.
export struct UnaryExpression {
    var op: UnaryOp;
    var operand: Expression;
    var loc: Loc;

    construct(operand: Expression, op: UnaryOp = UnaryOp.Neg, loc: Loc = Loc()) {
        this.operand = operand;
        this.op = op;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): UnaryExpression {
        return UnaryExpression(op = this.op, operand = this.operand.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("UnaryExpression");
        this.op.fingerprint(into);
        this.operand.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["op"] = this.op.to_json();
        out["operand"] = this.operand.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Cast`.
export struct CastExpression {
    var expr: Expression;
    var ty: TypeName;
    var loc: Loc;
    var kind: CastKind;

    construct(expr: Expression, ty: TypeName = TypeName(), loc: Loc = Loc(), kind: CastKind = CastKind.Static) {
        this.expr = expr;
        this.ty = ty;
        this.loc = loc;
        this.kind = kind;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CastExpression {
        return CastExpression(expr = this.expr.copy(), ty = this.ty.copy(), loc = this.loc, kind = this.kind);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CastExpression");
        this.expr.fingerprint(into);
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
        this.kind.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["expr"] = this.expr.to_json();
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        out["kind"] = this.kind.to_json();
        return out;
    }
}

## The fields of `Expression::Ternary`.
export struct TernaryExpression {
    var condition: Expression;
    var true_expr: Expression;
    var false_expr: Expression;

    construct(condition: Expression, true_expr: Expression, false_expr: Expression) {
        this.condition = condition;
        this.true_expr = true_expr;
        this.false_expr = false_expr;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TernaryExpression {
        return TernaryExpression(
            condition = this.condition.copy(), true_expr = this.true_expr.copy(), false_expr = this.false_expr.copy()
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TernaryExpression");
        this.condition.fingerprint(into);
        this.true_expr.fingerprint(into);
        this.false_expr.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        out["true_expr"] = this.true_expr.to_json();
        out["false_expr"] = this.false_expr.to_json();
        return out;
    }
}

## The fields of `Expression::Index`.
export struct IndexExpression {
    var lhs: Expression;
    var rhs: Expression;
    var loc: Loc;

    construct(lhs: Expression, rhs: Expression, loc: Loc = Loc()) {
        this.lhs = lhs;
        this.rhs = rhs;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): IndexExpression {
        return IndexExpression(lhs = this.lhs.copy(), rhs = this.rhs.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("IndexExpression");
        this.lhs.fingerprint(into);
        this.rhs.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["lhs"] = this.lhs.to_json();
        out["rhs"] = this.rhs.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::ArrayIndex`.
export struct ArrayIndexExpression {
    var ty: TypeName;
    var lhs: Expression;
    var rhs: Expression;
    var loc: Loc;

    construct(lhs: Expression, rhs: Expression, ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.lhs = lhs;
        this.rhs = rhs;
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ArrayIndexExpression {
        return ArrayIndexExpression(ty = this.ty.copy(), lhs = this.lhs.copy(), rhs = this.rhs.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ArrayIndexExpression");
        this.ty.fingerprint(into);
        this.lhs.fingerprint(into);
        this.rhs.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        out["lhs"] = this.lhs.to_json();
        out["rhs"] = this.rhs.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Simd`.
export struct SimdExpression {
    var op: SimdOp;
    var ty: TypeName;
    var args: Array<Expression>;
    var loc: Loc;

    construct(
        op: SimdOp = SimdOp.Splat,
        ty: TypeName = TypeName(),
        args: Array<Expression> = Array<Expression>(),
        loc: Loc = Loc()
    ) {
        this.op = op;
        this.ty = ty;
        this.args = args;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): SimdExpression {
        var _c45 = Array<Expression>();
        for (var _item45 in this.args) {
            _c45.append(_item45.copy());
        }
        return SimdExpression(op = this.op, ty = this.ty.copy(), args = _c45, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("SimdExpression");
        this.op.fingerprint(into);
        this.ty.fingerprint(into);
        into.add(this.args.count);
        for (var _item45 in this.args) {
            _item45.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["op"] = this.op.to_json();
        out["ty"] = this.ty.to_json();
        var _v45 = JsonValue.array();
        for (var _item45 in this.args) {
            _v45.append(_item45.to_json());
        }
        out["args"] = _v45;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::CountStep`.
export struct CountStepExpression {
    var field: CountField;
    var increment: bool;
    var atomic: bool;

    construct(field: CountField = CountField.Strong, increment: bool = false, atomic: bool = false) {
        this.field = field;
        this.increment = increment;
        this.atomic = atomic;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CountStepExpression {
        return CountStepExpression(field = this.field, increment = this.increment, atomic = this.atomic);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CountStepExpression");
        this.field.fingerprint(into);
        into.add(this.increment ? 1 : 0);
        into.add(this.atomic ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["field"] = this.field.to_json();
        out["increment"] = JsonValue.Bool(this.increment);
        out["atomic"] = JsonValue.Bool(this.atomic);
        return out;
    }
}

## The fields of `Expression::FunctionPointer`.
export struct FunctionPointerExpression {
    var owner: TypeName?;
    var function: String;
    var loc: Loc;

    construct(owner: TypeName? = Optional<TypeName>.Empty, function: String = "", loc: Loc = Loc()) {
        this.owner = owner;
        this.function = function;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FunctionPointerExpression {
        var _c51 = Optional<TypeName>.Empty;
        if (this.owner.is_value()) {
            _c51 = Optional<TypeName>.Value(this.owner.value().copy());
        }
        return FunctionPointerExpression(owner = _c51, function = this.function, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionPointerExpression");
        if (this.owner.is_value()) {
            this.owner.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add_text(this.function);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["owner"] = (this.owner.is_value() ? this.owner.value().to_json() : JsonValue.Null);
        out["function"] = JsonValue.String(this.function);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::FunctionCall`.
export struct FunctionCallExpression {
    var function: String;
    var args: Array<Expression>;
    var loc: Loc;

    construct(function: String = "", args: Array<Expression> = Array<Expression>(), loc: Loc = Loc()) {
        this.function = function;
        this.args = args;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FunctionCallExpression {
        var _c56 = Array<Expression>();
        for (var _item56 in this.args) {
            _c56.append(_item56.copy());
        }
        return FunctionCallExpression(function = this.function, args = _c56, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionCallExpression");
        into.add_text(this.function);
        into.add(this.args.count);
        for (var _item56 in this.args) {
            _item56.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["function"] = JsonValue.String(this.function);
        var _v56 = JsonValue.array();
        for (var _item56 in this.args) {
            _v56.append(_item56.to_json());
        }
        out["args"] = _v56;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::NamedArgument`.
export struct NamedArgumentExpression {
    var name: String;
    var value: Expression;
    var loc: Loc;

    construct(value: Expression, name: String = "", loc: Loc = Loc()) {
        this.value = value;
        this.name = name;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): NamedArgumentExpression {
        return NamedArgumentExpression(name = this.name, value = this.value.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("NamedArgumentExpression");
        into.add_text(this.name);
        this.value.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["value"] = this.value.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::DefaultArgument`.
export struct DefaultArgumentExpression {
    var ty: TypeName;

    construct(ty: TypeName = TypeName()) {
        this.ty = ty;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): DefaultArgumentExpression {
        return DefaultArgumentExpression(ty = this.ty.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("DefaultArgumentExpression");
        this.ty.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        return out;
    }
}

## The fields of `Expression::MethodCall`.
export struct MethodCallExpression {
    var this_value: Expression;
    var method: String;
    var args: Array<Expression>;
    var loc: Loc;

    construct(
        this_value: Expression, method: String = "", args: Array<Expression> = Array<Expression>(), loc: Loc = Loc()
    ) {
        this.this_value = this_value;
        this.method = method;
        this.args = args;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MethodCallExpression {
        var _c67 = Array<Expression>();
        for (var _item67 in this.args) {
            _c67.append(_item67.copy());
        }
        return MethodCallExpression(
            this_value = this.this_value.copy(), method = this.method, args = _c67, loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MethodCallExpression");
        this.this_value.fingerprint(into);
        into.add_text(this.method);
        into.add(this.args.count);
        for (var _item67 in this.args) {
            _item67.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["this"] = this.this_value.to_json();
        out["method"] = JsonValue.String(this.method);
        var _v67 = JsonValue.array();
        for (var _item67 in this.args) {
            _v67.append(_item67.to_json());
        }
        out["args"] = _v67;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::FunctionRef`.
export struct FunctionRefExpression {
    var function: String;
    var ty: TypeName;
    var loc: Loc;

    construct(function: String = "", ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.function = function;
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FunctionRefExpression {
        return FunctionRefExpression(function = this.function, ty = this.ty.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionRefExpression");
        into.add_text(this.function);
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["function"] = JsonValue.String(this.function);
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Invoke`.
export struct InvokeExpression {
    var callee: Expression;
    var args: Array<Expression>;

    construct(callee: Expression, args: Array<Expression> = Array<Expression>()) {
        this.callee = callee;
        this.args = args;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): InvokeExpression {
        var _c75 = Array<Expression>();
        for (var _item75 in this.args) {
            _c75.append(_item75.copy());
        }
        return InvokeExpression(callee = this.callee.copy(), args = _c75);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("InvokeExpression");
        this.callee.fingerprint(into);
        into.add(this.args.count);
        for (var _item75 in this.args) {
            _item75.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["callee"] = this.callee.to_json();
        var _v75 = JsonValue.array();
        for (var _item75 in this.args) {
            _v75.append(_item75.to_json());
        }
        out["args"] = _v75;
        return out;
    }
}

## The fields of `Expression::MakeClosure`.
export struct MakeClosureExpression {
    var value: Expression;
    var closure: String;
    var ty: TypeName;
    var loc: Loc;

    construct(value: Expression, closure: String = "", ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.value = value;
        this.closure = closure;
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MakeClosureExpression {
        return MakeClosureExpression(
            value = this.value.copy(), closure = this.closure, ty = this.ty.copy(), loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MakeClosureExpression");
        this.value.fingerprint(into);
        into.add_text(this.closure);
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["closure"] = JsonValue.String(this.closure);
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::CallPointer`.
export struct CallPointerExpression {
    var pointer: Expression;
    var args: Array<Expression>;

    construct(pointer: Expression, args: Array<Expression> = Array<Expression>()) {
        this.pointer = pointer;
        this.args = args;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CallPointerExpression {
        var _c84 = Array<Expression>();
        for (var _item84 in this.args) {
            _c84.append(_item84.copy());
        }
        return CallPointerExpression(pointer = this.pointer.copy(), args = _c84);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CallPointerExpression");
        this.pointer.fingerprint(into);
        into.add(this.args.count);
        for (var _item84 in this.args) {
            _item84.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["pointer"] = this.pointer.to_json();
        var _v84 = JsonValue.array();
        for (var _item84 in this.args) {
            _v84.append(_item84.to_json());
        }
        out["args"] = _v84;
        return out;
    }
}

## The fields of `Expression::Move`.
export struct MoveExpression {
    var value: Expression;
    var loc: Loc;

    construct(value: Expression, loc: Loc = Loc()) {
        this.value = value;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MoveExpression {
        return MoveExpression(value = this.value.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MoveExpression");
        this.value.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Destructure`.
export struct DestructureExpression {
    var value: Expression;
    var count: ulong;
    var loc: Loc;

    construct(value: Expression, count: ulong = 0, loc: Loc = Loc()) {
        this.value = value;
        this.count = count;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): DestructureExpression {
        return DestructureExpression(value = this.value.copy(), count = this.count, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("DestructureExpression");
        this.value.fingerprint(into);
        into.add(this.count as ulong);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["count"] = unsigned_json(this.count);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::StaticCase`.
export struct StaticCaseExpression {
    var ty: TypeName;
    var tag: long;

    construct(ty: TypeName = TypeName(), tag: long = 0) {
        this.ty = ty;
        this.tag = tag;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticCaseExpression {
        return StaticCaseExpression(ty = this.ty.copy(), tag = this.tag);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticCaseExpression");
        this.ty.fingerprint(into);
        into.add(this.tag as ulong);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        out["tag"] = JsonValue.Integer(this.tag as long);
        return out;
    }
}

## The fields of `Expression::StaticString`.
export struct StaticStringExpression {
    var value: String;
    var loc: Loc;

    construct(value: String = "", loc: Loc = Loc()) {
        this.value = value;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticStringExpression {
        return StaticStringExpression(value = this.value, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticStringExpression");
        into.add_text(this.value);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = JsonValue.String(this.value);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::Subject`.
export struct SubjectExpression {
    var id: ulong;
    var ty: TypeName;
    var loc: Loc;

    construct(id: ulong = 0, ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.id = id;
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): SubjectExpression {
        return SubjectExpression(id = this.id, ty = this.ty.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("SubjectExpression");
        into.add(this.id as ulong);
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = unsigned_json(this.id);
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::ToTrait`.
export struct ToTraitExpression {
    var value: Expression;
    var from: TypeName;
    var to: TypeName;
    var loc: Loc;

    construct(value: Expression, from: TypeName = TypeName(), to: TypeName = TypeName(), loc: Loc = Loc()) {
        this.value = value;
        this.from = from;
        this.to = to;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ToTraitExpression {
        return ToTraitExpression(
            value = this.value.copy(), from = this.from.copy(), to = this.to.copy(), loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ToTraitExpression");
        this.value.fingerprint(into);
        this.from.fingerprint(into);
        this.to.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["from"] = this.from.to_json();
        out["to"] = this.to.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression::FromTrait`.
export struct FromTraitExpression {
    var value: Expression;
    var from: TypeName;
    var to: TypeName;
    var candidates: Array<TypeName>;
    var test: bool;
    var loc: Loc;

    construct(
        value: Expression,
        from: TypeName = TypeName(),
        to: TypeName = TypeName(),
        candidates: Array<TypeName> = Array<TypeName>(),
        test: bool = false,
        loc: Loc = Loc()
    ) {
        this.value = value;
        this.from = from;
        this.to = to;
        this.candidates = candidates;
        this.test = test;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FromTraitExpression {
        var _c109 = Array<TypeName>();
        for (var _item109 in this.candidates) {
            _c109.append(_item109.copy());
        }
        return FromTraitExpression(
            value = this.value.copy(),
            from = this.from.copy(),
            to = this.to.copy(),
            candidates = _c109,
            test = this.test,
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FromTraitExpression");
        this.value.fingerprint(into);
        this.from.fingerprint(into);
        this.to.fingerprint(into);
        into.add(this.candidates.count);
        for (var _item109 in this.candidates) {
            _item109.fingerprint(into);
        }
        into.add(this.test ? 1 : 0);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["from"] = this.from.to_json();
        out["to"] = this.to.to_json();
        var _v109 = JsonValue.array();
        for (var _item109 in this.candidates) {
            _v109.append(_item109.to_json());
        }
        out["candidates"] = _v109;
        out["test"] = JsonValue.Bool(this.test);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `StaticValue` in `model.rs`.
export struct StaticValue {
    var expr: ast.Expression;
    var loc: Loc;

    construct(expr: ast.Expression, loc: Loc = Loc()) {
        this.expr = expr;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticValue {
        return StaticValue(expr = this.expr, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticValue");
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["expr"] = this.expr.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `StaticMember` in `model.rs`.
export struct StaticMember {
    var member: ast.Expression;
    var method: String;
    var args: Array<Expression>;
    var loc: Loc;
    var span: ast.Span;
    var argument_spans: Array<ast.Span>;

    construct(
        member: ast.Expression,
        method: String = "",
        args: Array<Expression> = Array<Expression>(),
        loc: Loc = Loc(),
        span: ast.Span = ast.Span(),
        argument_spans: Array<ast.Span> = Array<ast.Span>()
    ) {
        this.member = member;
        this.method = method;
        this.args = args;
        this.loc = loc;
        this.span = span;
        this.argument_spans = argument_spans;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticMember {
        var _c176 = Array<Expression>();
        for (var _item176 in this.args) {
            _c176.append(_item176.copy());
        }
        return StaticMember(
            member = this.member,
            method = this.method,
            args = _c176,
            loc = this.loc,
            span = this.span,
            argument_spans = this.argument_spans.copy()
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticMember");
        into.add_text(this.method);
        into.add(this.args.count);
        for (var _item176 in this.args) {
            _item176.fingerprint(into);
        }
        this.loc.fingerprint(into);
        into.add(this.argument_spans.count);
        for (var _item180 in this.argument_spans) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["member"] = this.member.to_json();
        out["method"] = JsonValue.String(this.method);
        var _v176 = JsonValue.array();
        for (var _item176 in this.args) {
            _v176.append(_item176.to_json());
        }
        out["args"] = _v176;
        out["loc"] = this.loc.to_json();
        out["span"] = this.span.to_json();
        var _v180 = JsonValue.array();
        for (var _item180 in this.argument_spans) {
            _v180.append(_item180.to_json());
        }
        out["argument_spans"] = _v180;
        return out;
    }
}

## `MatchArmTest` in `model.rs`.
export struct MatchArmTest {
    var subject: Expression;
    var patterns: Array<CasePattern>;
    var site: MatchSite;
    var element_names: Array<ElementName>;
    var guarded: bool;

    construct(
        subject: Expression,
        patterns: Array<CasePattern> = Array<CasePattern>(),
        site: MatchSite = MatchSite(),
        element_names: Array<ElementName> = Array<ElementName>(),
        guarded: bool = false
    ) {
        this.subject = subject;
        this.patterns = patterns;
        this.site = site;
        this.element_names = element_names;
        this.guarded = guarded;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MatchArmTest {
        var _c183 = Array<CasePattern>();
        for (var _item183 in this.patterns) {
            _c183.append(_item183.copy());
        }
        var _c186 = Array<ElementName>();
        for (var _item186 in this.element_names) {
            _c186.append(_item186.copy());
        }
        return MatchArmTest(
            subject = this.subject.copy(),
            patterns = _c183,
            site = this.site.copy(),
            element_names = _c186,
            guarded = this.guarded
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MatchArmTest");
        this.subject.fingerprint(into);
        into.add(this.patterns.count);
        for (var _item183 in this.patterns) {
            _item183.fingerprint(into);
        }
        this.site.fingerprint(into);
        into.add(this.element_names.count);
        for (var _item186 in this.element_names) {
            _item186.fingerprint(into);
        }
        into.add(this.guarded ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["subject"] = this.subject.to_json();
        var _v183 = JsonValue.array();
        for (var _item183 in this.patterns) {
            _v183.append(_item183.to_json());
        }
        out["patterns"] = _v183;
        out["site"] = this.site.to_json();
        var _v186 = JsonValue.array();
        for (var _item186 in this.element_names) {
            _v186.append(_item186.to_json());
        }
        out["element_names"] = _v186;
        out["guarded"] = JsonValue.Bool(this.guarded);
        return out;
    }
}

## `ElementName` in `model.rs`.
export struct ElementName {
    var name: String;
    var loc: Loc;
    var declared: bool;
    var missing: Optional<(String, Loc)>;

    construct(
        name: String = "",
        loc: Loc = Loc(),
        declared: bool = false,
        missing: Optional<(String, Loc)> = Optional<(String, Loc)>.Empty
    ) {
        this.name = name;
        this.loc = loc;
        this.declared = declared;
        this.missing = missing;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ElementName {
        var _c192 = Optional<(String, Loc)>.Empty;
        if (this.missing.is_value()) {
            var (_t193_0, _t193_1) = this.missing.value();
            _c192 = Optional<(String, Loc)>.Value((_t193_0, _t193_1));
        }
        return ElementName(name = this.name, loc = this.loc, declared = this.declared, missing = _c192);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ElementName");
        into.add_text(this.name);
        this.loc.fingerprint(into);
        into.add(this.declared ? 1 : 0);
        if (this.missing.is_value()) {
            var (_t193_0, _t193_1) = this.missing.value();
            into.add_text(_t193_0);
            _t193_1.fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["loc"] = this.loc.to_json();
        out["declared"] = JsonValue.Bool(this.declared);
        var _v192 = JsonValue.Null;
        if (this.missing.is_value()) {
            var _v193 = JsonValue.array();
            var _t193 = this.missing.value();
            var (_t193_0, _t193_1) = _t193;
            _v193.append(JsonValue.String(_t193_0));
            _v193.append(_t193_1.to_json());
            _v192 = _v193;
        }
        out["missing"] = _v192;
        return out;
    }
}

## `MatchSite` in `model.rs`.
export struct MatchSite {
    var id: ulong;
    var keyword: Loc;
    var else_arm: Loc?;
    var partial: bool;
    var no_bindings: bool;

    construct(
        id: ulong = 0,
        keyword: Loc = Loc(),
        else_arm: Loc? = Optional<Loc>.Empty,
        partial: bool = false,
        no_bindings: bool = false
    ) {
        this.id = id;
        this.keyword = keyword;
        this.else_arm = else_arm;
        this.partial = partial;
        this.no_bindings = no_bindings;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MatchSite {
        return MatchSite(
            id = this.id,
            keyword = this.keyword,
            else_arm = this.else_arm,
            partial = this.partial,
            no_bindings = this.no_bindings
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("MatchSite");
        into.add(this.id as ulong);
        this.keyword.fingerprint(into);
        if (this.else_arm.is_value()) {
            this.else_arm.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.partial ? 1 : 0);
        into.add(this.no_bindings ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = unsigned_json(this.id);
        out["keyword"] = this.keyword.to_json();
        out["else_arm"] = (this.else_arm.is_value() ? this.else_arm.value().to_json() : JsonValue.Null);
        out["partial"] = JsonValue.Bool(this.partial);
        out["no_bindings"] = JsonValue.Bool(this.no_bindings);
        return out;
    }
}

## `WithSubject` in `model.rs`.
export struct WithSubject {
    var id: ulong;
    var subject: Expression;
    var body: Expression;
    var null_message: String?;
    var loc: Loc;

    construct(
        subject: Expression,
        body: Expression,
        id: ulong = 0,
        null_message: String? = Optional<String>.Empty,
        loc: Loc = Loc()
    ) {
        this.subject = subject;
        this.body = body;
        this.id = id;
        this.null_message = null_message;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): WithSubject {
        return WithSubject(
            id = this.id,
            subject = this.subject.copy(),
            body = this.body.copy(),
            null_message = this.null_message,
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("WithSubject");
        into.add(this.id as ulong);
        this.subject.fingerprint(into);
        this.body.fingerprint(into);
        if (this.null_message.is_value()) {
            into.add_text(this.null_message.value());
            into.add(1);
        } else {
            into.add(0);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = unsigned_json(this.id);
        out["subject"] = this.subject.to_json();
        out["body"] = this.body.to_json();
        out["null_message"] = (this.null_message.is_value() ?
            JsonValue.String(this.null_message.value()) :
            JsonValue.Null);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CaseValue` in `model.rs`.
export struct CaseValue {
    var subject: Expression;
    var name: String;
    var choices: Array<CaseChoice>;
    var loc: Loc;

    construct(
        subject: Expression, name: String = "", choices: Array<CaseChoice> = Array<CaseChoice>(), loc: Loc = Loc()
    ) {
        this.subject = subject;
        this.name = name;
        this.choices = choices;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CaseValue {
        var _c210 = Array<CaseChoice>();
        for (var _item210 in this.choices) {
            _c210.append(_item210.copy());
        }
        return CaseValue(subject = this.subject.copy(), name = this.name, choices = _c210, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CaseValue");
        this.subject.fingerprint(into);
        into.add_text(this.name);
        into.add(this.choices.count);
        for (var _item210 in this.choices) {
            _item210.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["subject"] = this.subject.to_json();
        out["name"] = JsonValue.String(this.name);
        var _v210 = JsonValue.array();
        for (var _item210 in this.choices) {
            _v210.append(_item210.to_json());
        }
        out["choices"] = _v210;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CaseChoice` in `model.rs`.
export struct CaseChoice {
    var case: String;
    var case_loc: Loc;
    var ty: TypeName?;
    var index: ulong;
    var bindings: Array<Loc>;
    var loc: Loc;

    construct(
        case: String = "",
        case_loc: Loc = Loc(),
        ty: TypeName? = Optional<TypeName>.Empty,
        index: ulong = 0,
        bindings: Array<Loc> = Array<Loc>(),
        loc: Loc = Loc()
    ) {
        this.case = case;
        this.case_loc = case_loc;
        this.ty = ty;
        this.index = index;
        this.bindings = bindings;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CaseChoice {
        var _c215 = Optional<TypeName>.Empty;
        if (this.ty.is_value()) {
            _c215 = Optional<TypeName>.Value(this.ty.value().copy());
        }
        return CaseChoice(
            case = this.case,
            case_loc = this.case_loc,
            ty = _c215,
            index = this.index,
            bindings = this.bindings.copy(),
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CaseChoice");
        into.add_text(this.case);
        this.case_loc.fingerprint(into);
        if (this.ty.is_value()) {
            this.ty.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.index as ulong);
        into.add(this.bindings.count);
        for (var _item218 in this.bindings) {
            _item218.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["case"] = JsonValue.String(this.case);
        out["case_loc"] = this.case_loc.to_json();
        out["ty"] = (this.ty.is_value() ? this.ty.value().to_json() : JsonValue.Null);
        out["index"] = unsigned_json(this.index);
        var _v218 = JsonValue.array();
        for (var _item218 in this.bindings) {
            _v218.append(_item218.to_json());
        }
        out["bindings"] = _v218;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CasePattern` in `model.rs`.
export struct CasePattern {
    var qualifier: TypeName?;
    var case: String;
    var loc: Loc;
    var bindings: Array<CasePattern>?;
    var literal: Expression?;
    var elements: Array<CasePattern>?;
    var range: bool;
    var constant: bool;
    var values: Optional<(long, long)>;
    var ty: TypeName?;

    construct(
        qualifier: TypeName? = Optional<TypeName>.Empty,
        case: String = "",
        loc: Loc = Loc(),
        bindings: Array<CasePattern>? = Optional<Array<CasePattern>>.Empty,
        literal: Expression? = Optional<Expression>.Empty,
        elements: Array<CasePattern>? = Optional<Array<CasePattern>>.Empty,
        range: bool = false,
        constant: bool = false,
        values: Optional<(long, long)> = Optional<(long, long)>.Empty,
        ty: TypeName? = Optional<TypeName>.Empty
    ) {
        this.qualifier = qualifier;
        this.case = case;
        this.loc = loc;
        this.bindings = bindings;
        this.literal = literal;
        this.elements = elements;
        this.range = range;
        this.constant = constant;
        this.values = values;
        this.ty = ty;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CasePattern {
        var _c221 = Optional<TypeName>.Empty;
        if (this.qualifier.is_value()) {
            _c221 = Optional<TypeName>.Value(this.qualifier.value().copy());
        }
        var _c225 = Optional<Array<CasePattern>>.Empty;
        if (this.bindings.is_value()) {
            var _c226 = Array<CasePattern>();
            for (var _item226 in this.bindings.value()) {
                _c226.append(_item226.copy());
            }
            _c225 = Optional<Array<CasePattern>>.Value(_c226);
        }
        var _c228 = Optional<Expression>.Empty;
        if (this.literal.is_value()) {
            _c228 = Optional<Expression>.Value(this.literal.value().copy());
        }
        var _c230 = Optional<Array<CasePattern>>.Empty;
        if (this.elements.is_value()) {
            var _c231 = Array<CasePattern>();
            for (var _item231 in this.elements.value()) {
                _c231.append(_item231.copy());
            }
            _c230 = Optional<Array<CasePattern>>.Value(_c231);
        }
        var _c235 = Optional<(long, long)>.Empty;
        if (this.values.is_value()) {
            var (_t236_0, _t236_1) = this.values.value();
            _c235 = Optional<(long, long)>.Value((_t236_0, _t236_1));
        }
        var _c239 = Optional<TypeName>.Empty;
        if (this.ty.is_value()) {
            _c239 = Optional<TypeName>.Value(this.ty.value().copy());
        }
        return CasePattern(
            qualifier = _c221,
            case = this.case,
            loc = this.loc,
            bindings = _c225,
            literal = _c228,
            elements = _c230,
            range = this.range,
            constant = this.constant,
            values = _c235,
            ty = _c239
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CasePattern");
        if (this.qualifier.is_value()) {
            this.qualifier.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add_text(this.case);
        this.loc.fingerprint(into);
        if (this.bindings.is_value()) {
            into.add(this.bindings.value().count);
            for (var _item226 in this.bindings.value()) {
                _item226.fingerprint(into);
            }
            into.add(1);
        } else {
            into.add(0);
        }
        if (this.literal.is_value()) {
            this.literal.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        if (this.elements.is_value()) {
            into.add(this.elements.value().count);
            for (var _item231 in this.elements.value()) {
                _item231.fingerprint(into);
            }
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.range ? 1 : 0);
        into.add(this.constant ? 1 : 0);
        if (this.values.is_value()) {
            var (_t236_0, _t236_1) = this.values.value();
            into.add(_t236_0 as ulong);
            into.add(_t236_1 as ulong);
            into.add(1);
        } else {
            into.add(0);
        }
        if (this.ty.is_value()) {
            this.ty.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["qualifier"] = (this.qualifier.is_value() ? this.qualifier.value().to_json() : JsonValue.Null);
        out["case"] = JsonValue.String(this.case);
        out["loc"] = this.loc.to_json();
        var _v225 = JsonValue.Null;
        if (this.bindings.is_value()) {
            var _v226 = JsonValue.array();
            for (var _item226 in this.bindings.value()) {
                _v226.append(_item226.to_json());
            }
            _v225 = _v226;
        }
        out["bindings"] = _v225;
        out["literal"] = (this.literal.is_value() ? this.literal.value().to_json() : JsonValue.Null);
        var _v230 = JsonValue.Null;
        if (this.elements.is_value()) {
            var _v231 = JsonValue.array();
            for (var _item231 in this.elements.value()) {
                _v231.append(_item231.to_json());
            }
            _v230 = _v231;
        }
        out["elements"] = _v230;
        out["range"] = JsonValue.Bool(this.range);
        out["constant"] = JsonValue.Bool(this.constant);
        var _v235 = JsonValue.Null;
        if (this.values.is_value()) {
            var _v236 = JsonValue.array();
            var _t236 = this.values.value();
            var (_t236_0, _t236_1) = _t236;
            _v236.append(JsonValue.Integer(_t236_0 as long));
            _v236.append(JsonValue.Integer(_t236_1 as long));
            _v235 = _v236;
        }
        out["values"] = _v235;
        out["ty"] = (this.ty.is_value() ? this.ty.value().to_json() : JsonValue.Null);
        return out;
    }
}

## `EnumDef` in `model.rs`.
export struct EnumDef {
    var name: String;
    var representation: TypeName;
    var cases: Array<EnumCaseDef>;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;

    construct(
        name: String = "",
        representation: TypeName = TypeName(),
        cases: Array<EnumCaseDef> = Array<EnumCaseDef>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc()
    ) {
        this.name = name;
        this.representation = representation;
        this.cases = cases;
        this.attributes = attributes;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): EnumDef {
        var _c243 = Array<EnumCaseDef>();
        for (var _item243 in this.cases) {
            _c243.append(_item243.copy());
        }
        return EnumDef(
            name = this.name,
            representation = this.representation.copy(),
            cases = _c243,
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("EnumDef");
        into.add_text(this.name);
        this.representation.fingerprint(into);
        into.add(this.cases.count);
        for (var _item243 in this.cases) {
            _item243.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item245 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["representation"] = this.representation.to_json();
        var _v243 = JsonValue.array();
        for (var _item243 in this.cases) {
            _v243.append(_item243.to_json());
        }
        out["cases"] = _v243;
        var _v245 = JsonValue.array();
        for (var _item245 in this.attributes) {
            _v245.append(_item245.to_json());
        }
        out["attributes"] = _v245;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `EnumCaseDef` in `model.rs`.
export struct EnumCaseDef {
    var name: String;
    var value: long;
    var payload: Array<(String, Loc)>;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;

    construct(
        name: String = "",
        value: long = 0,
        payload: Array<(String, Loc)> = Array<(String, Loc)>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc()
    ) {
        this.name = name;
        this.value = value;
        this.payload = payload;
        this.attributes = attributes;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): EnumCaseDef {
        var _c250 = Array<(String, Loc)>();
        for (var _item250 in this.payload) {
            var (_t251_0, _t251_1) = _item250;
            _c250.append((_t251_0, _t251_1));
        }
        return EnumCaseDef(
            name = this.name, value = this.value, payload = _c250, attributes = this.attributes.copy(), loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("EnumCaseDef");
        into.add_text(this.name);
        into.add(this.value as ulong);
        into.add(this.payload.count);
        for (var _item250 in this.payload) {
            var (_t251_0, _t251_1) = _item250;
            into.add_text(_t251_0);
            _t251_1.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item254 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["value"] = JsonValue.Integer(this.value as long);
        var _v250 = JsonValue.array();
        for (var _item250 in this.payload) {
            var _v251 = JsonValue.array();
            var _t251 = _item250;
            var (_t251_0, _t251_1) = _t251;
            _v251.append(JsonValue.String(_t251_0));
            _v251.append(_t251_1.to_json());
            _v250.append(_v251);
        }
        out["payload"] = _v250;
        var _v254 = JsonValue.array();
        for (var _item254 in this.attributes) {
            _v254.append(_item254.to_json());
        }
        out["attributes"] = _v254;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `ClosureLiteral` in `model.rs`.
export struct ClosureLiteral {
    var parameters: Array<VariableDef>;
    var ty: TypeName;
    var body: Block;
    var expression_body: bool;
    var loc: Loc;

    construct(
        parameters: Array<VariableDef> = Array<VariableDef>(),
        ty: TypeName = TypeName(),
        body: Block = Block(),
        expression_body: bool = false,
        loc: Loc = Loc()
    ) {
        this.parameters = parameters;
        this.ty = ty;
        this.body = body;
        this.expression_body = expression_body;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ClosureLiteral {
        var _c257 = Array<VariableDef>();
        for (var _item257 in this.parameters) {
            _c257.append(_item257.copy());
        }
        return ClosureLiteral(
            parameters = _c257,
            ty = this.ty.copy(),
            body = this.body.copy(),
            expression_body = this.expression_body,
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ClosureLiteral");
        into.add(this.parameters.count);
        for (var _item257 in this.parameters) {
            _item257.fingerprint(into);
        }
        this.ty.fingerprint(into);
        this.body.fingerprint(into);
        into.add(this.expression_body ? 1 : 0);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v257 = JsonValue.array();
        for (var _item257 in this.parameters) {
            _v257.append(_item257.to_json());
        }
        out["parameters"] = _v257;
        out["ty"] = this.ty.to_json();
        out["body"] = this.body.to_json();
        out["expression_body"] = JsonValue.Bool(this.expression_body);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CountField` in `model.rs`.
export enum CountField {
    Strong,
    Weak,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Strong => {
                into.add(0);
            }
            Weak => {
                into.add(1);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Strong => {
                return JsonValue.String("Strong");
            }
            Weak => {
                return JsonValue.String("Weak");
            }
        }
    }
}

## `WeakOp` in `model.rs`.
export enum WeakOp {
    From,
    Upgrade,
    Expired,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            From => {
                into.add(0);
            }
            Upgrade => {
                into.add(1);
            }
            Expired => {
                into.add(2);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            From => {
                return JsonValue.String("From");
            }
            Upgrade => {
                return JsonValue.String("Upgrade");
            }
            Expired => {
                return JsonValue.String("Expired");
            }
        }
    }
}

## `Block` in `model.rs`.
export struct Block {
    var name: String;
    var items: Array<Statement>;
    var attributes: Array<ast.Attribute>;

    construct(
        name: String = "",
        items: Array<Statement> = Array<Statement>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>()
    ) {
        this.name = name;
        this.items = items;
        this.attributes = attributes;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Block {
        var _c264 = Array<Statement>();
        for (var _item264 in this.items) {
            _c264.append(_item264.copy());
        }
        return Block(name = this.name, items = _c264, attributes = this.attributes.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Block");
        into.add_text(this.name);
        into.add(this.items.count);
        for (var _item264 in this.items) {
            _item264.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item266 in this.attributes) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v264 = JsonValue.array();
        for (var _item264 in this.items) {
            _v264.append(_item264.to_json());
        }
        out["items"] = _v264;
        var _v266 = JsonValue.array();
        for (var _item266 in this.attributes) {
            _v266.append(_item266.to_json());
        }
        out["attributes"] = _v266;
        return out;
    }
}

## `Branch` in `model.rs`.
export struct Branch {
    var condition: Expression;
    var if_block: Block;
    var else_block: Block?;

    construct(condition: Expression, if_block: Block = Block(), else_block: Block? = Optional<Block>.Empty) {
        this.condition = condition;
        this.if_block = if_block;
        this.else_block = else_block;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Branch {
        var _c270 = Optional<Block>.Empty;
        if (this.else_block.is_value()) {
            _c270 = Optional<Block>.Value(this.else_block.value().copy());
        }
        return Branch(condition = this.condition.copy(), if_block = this.if_block.copy(), else_block = _c270);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Branch");
        this.condition.fingerprint(into);
        this.if_block.fingerprint(into);
        if (this.else_block.is_value()) {
            this.else_block.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        out["if_block"] = this.if_block.to_json();
        out["else_block"] = (this.else_block.is_value() ? this.else_block.value().to_json() : JsonValue.Null);
        return out;
    }
}

## `While` in `model.rs`.
export struct While {
    var condition: Expression;
    var block: Block;

    construct(condition: Expression, block: Block = Block()) {
        this.condition = condition;
        this.block = block;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): While {
        return While(condition = this.condition.copy(), block = this.block.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("While");
        this.condition.fingerprint(into);
        this.block.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        out["block"] = this.block.to_json();
        return out;
    }
}

## `ReturnStatement` in `model.rs`.
export struct ReturnStatement {
    var expr: Expression?;
    var loc: Loc;

    construct(expr: Expression? = Optional<Expression>.Empty, loc: Loc = Loc()) {
        this.expr = expr;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ReturnStatement {
        var _c274 = Optional<Expression>.Empty;
        if (this.expr.is_value()) {
            _c274 = Optional<Expression>.Value(this.expr.value().copy());
        }
        return ReturnStatement(expr = _c274, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ReturnStatement");
        if (this.expr.is_value()) {
            this.expr.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["expr"] = (this.expr.is_value() ? this.expr.value().to_json() : JsonValue.Null);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `LoopBreakKind` in `model.rs`.
export enum LoopBreakKind {
    Break,
    Continue,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Break => {
                into.add(0);
            }
            Continue => {
                into.add(1);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Break => {
                return JsonValue.String("Break");
            }
            Continue => {
                return JsonValue.String("Continue");
            }
        }
    }
}

## `LoopBreak` in `model.rs`.
export struct LoopBreak {
    var kind: LoopBreakKind;

    construct(kind: LoopBreakKind = LoopBreakKind.Break) {
        this.kind = kind;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): LoopBreak {
        return LoopBreak(kind = this.kind);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("LoopBreak");
        this.kind.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["kind"] = this.kind.to_json();
        return out;
    }
}

## `Statement` in `model.rs`.
export enum Statement {
    Expression(value: Expression),
    Block(value: Block),
    Declaration(value: Declaration),
    Branch(value: Branch),
    While(value: While),
    Return(value: ReturnStatement),
    LoopBreak(value: LoopBreak),
    Static(value: StaticBlock),
    StaticPass(value: StaticPass),

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Expression(value) => {
                into.add(0);
                value.fingerprint(into);
            }
            Block(value) => {
                into.add(1);
                value.fingerprint(into);
            }
            Declaration(value) => {
                into.add(2);
                value.fingerprint(into);
            }
            Branch(value) => {
                into.add(3);
                value.fingerprint(into);
            }
            While(value) => {
                into.add(4);
                value.fingerprint(into);
            }
            Return(value) => {
                into.add(5);
                value.fingerprint(into);
            }
            LoopBreak(value) => {
                into.add(6);
                value.fingerprint(into);
            }
            Static(value) => {
                into.add(7);
                value.fingerprint(into);
            }
            StaticPass(value) => {
                into.add(8);
                value.fingerprint(into);
            }
        }
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Statement {
        match (this) {
            Expression(value) => {
                return Statement.Expression(value.copy());
            }
            Block(value) => {
                return Statement.Block(value.copy());
            }
            Declaration(value) => {
                return Statement.Declaration(value.copy());
            }
            Branch(value) => {
                return Statement.Branch(value.copy());
            }
            While(value) => {
                return Statement.While(value.copy());
            }
            Return(value) => {
                return Statement.Return(value.copy());
            }
            LoopBreak(value) => {
                return Statement.LoopBreak(value.copy());
            }
            Static(value) => {
                return Statement.Static(value.copy());
            }
            StaticPass(value) => {
                return Statement.StaticPass(value.copy());
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Expression(value) => {
                return _tagged("Expression", value.to_json());
            }
            Block(value) => {
                return _tagged("Block", value.to_json());
            }
            Declaration(value) => {
                return _tagged("Declaration", value.to_json());
            }
            Branch(value) => {
                return _tagged("Branch", value.to_json());
            }
            While(value) => {
                return _tagged("While", value.to_json());
            }
            Return(value) => {
                return _tagged("Return", value.to_json());
            }
            LoopBreak(value) => {
                return _tagged("LoopBreak", value.to_json());
            }
            Static(value) => {
                return _tagged("Static", value.to_json());
            }
            StaticPass(value) => {
                return _tagged("StaticPass", value.to_json());
            }
        }
    }
}

## `StaticPass` in `model.rs`.
export struct StaticPass {
    var loc: Loc;
    var stop: bool;
    var values: Array<(String, StaticConstant)>;
    var header: uint?;
    var lines: Array<(Loc, uint)>;

    construct(
        loc: Loc = Loc(),
        stop: bool = false,
        values: Array<(String, StaticConstant)> = Array<(String, StaticConstant)>(),
        header: uint? = Optional<uint>.Empty,
        lines: Array<(Loc, uint)> = Array<(Loc, uint)>()
    ) {
        this.loc = loc;
        this.stop = stop;
        this.values = values;
        this.header = header;
        this.lines = lines;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticPass {
        var _c290 = Array<(String, StaticConstant)>();
        for (var _item290 in this.values) {
            var (_t291_0, _t291_1) = _item290;
            _c290.append((_t291_0, _t291_1.copy()));
        }
        var _c296 = Array<(Loc, uint)>();
        for (var _item296 in this.lines) {
            var (_t297_0, _t297_1) = _item296;
            _c296.append((_t297_0, _t297_1));
        }
        return StaticPass(loc = this.loc, stop = this.stop, values = _c290, header = this.header, lines = _c296);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticPass");
        this.loc.fingerprint(into);
        into.add(this.stop ? 1 : 0);
        into.add(this.values.count);
        for (var _item290 in this.values) {
            var (_t291_0, _t291_1) = _item290;
            into.add_text(_t291_0);
            _t291_1.fingerprint(into);
        }
        if (this.header.is_value()) {
            into.add(this.header.value() as ulong);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.lines.count);
        for (var _item296 in this.lines) {
            var (_t297_0, _t297_1) = _item296;
            _t297_0.fingerprint(into);
            into.add(_t297_1 as ulong);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["loc"] = this.loc.to_json();
        out["stop"] = JsonValue.Bool(this.stop);
        var _v290 = JsonValue.array();
        for (var _item290 in this.values) {
            var _v291 = JsonValue.array();
            var _t291 = _item290;
            var (_t291_0, _t291_1) = _t291;
            _v291.append(JsonValue.String(_t291_0));
            _v291.append(_t291_1.to_json());
            _v290.append(_v291);
        }
        out["values"] = _v290;
        out["header"] = (this.header.is_value() ? JsonValue.Integer(this.header.value() as long) : JsonValue.Null);
        var _v296 = JsonValue.array();
        for (var _item296 in this.lines) {
            var _v297 = JsonValue.array();
            var _t297 = _item296;
            var (_t297_0, _t297_1) = _t297;
            _v297.append(_t297_0.to_json());
            _v297.append(JsonValue.Integer(_t297_1 as long));
            _v296.append(_v297);
        }
        out["lines"] = _v296;
        return out;
    }
}

## `StaticConstant` in `model.rs`.
export enum StaticConstant {
    Int(value: long),
    Float(value: double),
    Bool(value: bool),
    String(value: String),
    Record(node: RecordStaticConstant),

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Int(value) => {
                into.add(0);
                into.add(value as ulong);
            }
            Float(value) => {
                into.add(1);
                into.add_text($"{value}");
            }
            Bool(value) => {
                into.add(2);
                into.add(value ? 1 : 0);
            }
            String(value) => {
                into.add(3);
                into.add_text(value);
            }
            Record(node) => {
                into.add(4);
                node.fingerprint(into);
            }
        }
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticConstant {
        match (this) {
            Int(value) => {
                return StaticConstant.Int(value);
            }
            Float(value) => {
                return StaticConstant.Float(value);
            }
            Bool(value) => {
                return StaticConstant.Bool(value);
            }
            String(value) => {
                return StaticConstant.String(value);
            }
            Record(node) => {
                return StaticConstant.Record(node.copy());
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Int(value) => {
                return _tagged("Int", JsonValue.Integer(value as long));
            }
            Float(value) => {
                return _tagged("Float", JsonValue.Number(value));
            }
            Bool(value) => {
                return _tagged("Bool", JsonValue.Bool(value));
            }
            String(value) => {
                return _tagged("String", JsonValue.String(value));
            }
            Record(node) => {
                return _tagged("Record", node.to_json());
            }
        }
    }
}

## The fields of `StaticConstant::Record`.
export struct RecordStaticConstant {
    var name: String;
    var fields: Array<(String, StaticConstant)>;

    construct(name: String = "", fields: Array<(String, StaticConstant)> = Array<(String, StaticConstant)>()) {
        this.name = name;
        this.fields = fields;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): RecordStaticConstant {
        var _c301 = Array<(String, StaticConstant)>();
        for (var _item301 in this.fields) {
            var (_t302_0, _t302_1) = _item301;
            _c301.append((_t302_0, _t302_1.copy()));
        }
        return RecordStaticConstant(name = this.name, fields = _c301);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("RecordStaticConstant");
        into.add_text(this.name);
        into.add(this.fields.count);
        for (var _item301 in this.fields) {
            var (_t302_0, _t302_1) = _item301;
            into.add_text(_t302_0);
            _t302_1.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v301 = JsonValue.array();
        for (var _item301 in this.fields) {
            var _v302 = JsonValue.array();
            var _t302 = _item301;
            var (_t302_0, _t302_1) = _t302;
            _v302.append(JsonValue.String(_t302_0));
            _v302.append(_t302_1.to_json());
            _v301.append(_v302);
        }
        out["fields"] = _v301;
        return out;
    }
}

## `StaticBlock` in `model.rs`.
export struct StaticBlock {
    var captures: Array<String>;
    var items: Array<StaticItem>;
    var type_map: Array<(String, TypeName)>;
    var loc: Loc;
    var span: ast.Span;

    construct(
        captures: Array<String> = Array<String>(),
        items: Array<StaticItem> = Array<StaticItem>(),
        type_map: Array<(String, TypeName)> = Array<(String, TypeName)>(),
        loc: Loc = Loc(),
        span: ast.Span = ast.Span()
    ) {
        this.captures = captures;
        this.items = items;
        this.type_map = type_map;
        this.loc = loc;
        this.span = span;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticBlock {
        var _c311 = Array<StaticItem>();
        for (var _item311 in this.items) {
            _c311.append(_item311.copy());
        }
        var _c313 = Array<(String, TypeName)>();
        for (var _item313 in this.type_map) {
            var (_t314_0, _t314_1) = _item313;
            _c313.append((_t314_0, _t314_1.copy()));
        }
        return StaticBlock(
            captures = this.captures.copy(), items = _c311, type_map = _c313, loc = this.loc, span = this.span
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticBlock");
        into.add(this.captures.count);
        for (var _item309 in this.captures) {
            into.add_text(_item309);
        }
        into.add(this.items.count);
        for (var _item311 in this.items) {
            _item311.fingerprint(into);
        }
        into.add(this.type_map.count);
        for (var _item313 in this.type_map) {
            var (_t314_0, _t314_1) = _item313;
            into.add_text(_t314_0);
            _t314_1.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v309 = JsonValue.array();
        for (var _item309 in this.captures) {
            _v309.append(JsonValue.String(_item309));
        }
        out["captures"] = _v309;
        var _v311 = JsonValue.array();
        for (var _item311 in this.items) {
            _v311.append(_item311.to_json());
        }
        out["items"] = _v311;
        var _v313 = JsonValue.array();
        for (var _item313 in this.type_map) {
            var _v314 = JsonValue.array();
            var _t314 = _item313;
            var (_t314_0, _t314_1) = _t314;
            _v314.append(JsonValue.String(_t314_0));
            _v314.append(_t314_1.to_json());
            _v313.append(_v314);
        }
        out["type_map"] = _v313;
        out["loc"] = this.loc.to_json();
        out["span"] = this.span.to_json();
        return out;
    }
}

## `ModuleStaticBlock` in `model.rs`.
export struct ModuleStaticBlock {
    var block: StaticBlock;
    var constants: Array<(String, Loc)>;

    construct(block: StaticBlock = StaticBlock(), constants: Array<(String, Loc)> = Array<(String, Loc)>()) {
        this.block = block;
        this.constants = constants;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ModuleStaticBlock {
        var _c320 = Array<(String, Loc)>();
        for (var _item320 in this.constants) {
            var (_t321_0, _t321_1) = _item320;
            _c320.append((_t321_0, _t321_1));
        }
        return ModuleStaticBlock(block = this.block.copy(), constants = _c320);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ModuleStaticBlock");
        this.block.fingerprint(into);
        into.add(this.constants.count);
        for (var _item320 in this.constants) {
            var (_t321_0, _t321_1) = _item320;
            into.add_text(_t321_0);
            _t321_1.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["block"] = this.block.to_json();
        var _v320 = JsonValue.array();
        for (var _item320 in this.constants) {
            var _v321 = JsonValue.array();
            var _t321 = _item320;
            var (_t321_0, _t321_1) = _t321;
            _v321.append(JsonValue.String(_t321_0));
            _v321.append(_t321_1.to_json());
            _v320.append(_v321);
        }
        out["constants"] = _v320;
        return out;
    }
}

## `StaticItem` in `model.rs`.
export enum StaticItem {
    For(node: ForStaticItem),
    While(node: WhileStaticItem),
    Jump(node: JumpStaticItem),
    If(node: IfStaticItem),
    EmitIf(node: EmitIfStaticItem),
    Block(value: Array<StaticItem>),
    Var(node: VarStaticItem),
    Evaluate(value: ast.Expression),
    Emit(v0: Statement, v1: ast.Span),

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            For(node) => {
                into.add(0);
                node.fingerprint(into);
            }
            While(node) => {
                into.add(1);
                node.fingerprint(into);
            }
            Jump(node) => {
                into.add(2);
                node.fingerprint(into);
            }
            If(node) => {
                into.add(3);
                node.fingerprint(into);
            }
            EmitIf(node) => {
                into.add(4);
                node.fingerprint(into);
            }
            Block(value) => {
                into.add(5);
                into.add(value.count);
                for (var _item350 in value) {
                    _item350.fingerprint(into);
                }
            }
            Var(node) => {
                into.add(6);
                node.fingerprint(into);
            }
            Evaluate(value) => {
                into.add(7);
            }
            Emit(v0, v1) => {
                into.add(8);
                v0.fingerprint(into);
            }
        }
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StaticItem {
        match (this) {
            For(node) => {
                return StaticItem.For(node.copy());
            }
            While(node) => {
                return StaticItem.While(node.copy());
            }
            Jump(node) => {
                return StaticItem.Jump(node.copy());
            }
            If(node) => {
                return StaticItem.If(node.copy());
            }
            EmitIf(node) => {
                return StaticItem.EmitIf(node.copy());
            }
            Block(value) => {
                var _c350 = Array<StaticItem>();
                for (var _item350 in value) {
                    _c350.append(_item350.copy());
                }
                return StaticItem.Block(_c350);
            }
            Var(node) => {
                return StaticItem.Var(node.copy());
            }
            Evaluate(value) => {
                return StaticItem.Evaluate(value);
            }
            Emit(v0, v1) => {
                return StaticItem.Emit(v0.copy(), v1);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            For(node) => {
                return _tagged("For", node.to_json());
            }
            While(node) => {
                return _tagged("While", node.to_json());
            }
            Jump(node) => {
                return _tagged("Jump", node.to_json());
            }
            If(node) => {
                return _tagged("If", node.to_json());
            }
            EmitIf(node) => {
                return _tagged("EmitIf", node.to_json());
            }
            Block(value) => {
                var _v350 = JsonValue.array();
                for (var _item350 in value) {
                    _v350.append(_item350.to_json());
                }
                return _tagged("Block", _v350);
            }
            Var(node) => {
                return _tagged("Var", node.to_json());
            }
            Evaluate(value) => {
                return _tagged("Evaluate", value.to_json());
            }
            Emit(v0, v1) => {
                var items = JsonValue.array();
                items.append(v0.to_json());
                items.append(v1.to_json());
                return _tagged("Emit", items);
            }
        }
    }
}

## The fields of `StaticItem::For`.
export struct ForStaticItem {
    var name: String;
    var iterable: ast.Expression;
    var body: Array<StaticItem>;
    var loc: Loc;

    construct(
        iterable: ast.Expression, name: String = "", body: Array<StaticItem> = Array<StaticItem>(), loc: Loc = Loc()
    ) {
        this.iterable = iterable;
        this.name = name;
        this.body = body;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ForStaticItem {
        var _c326 = Array<StaticItem>();
        for (var _item326 in this.body) {
            _c326.append(_item326.copy());
        }
        return ForStaticItem(name = this.name, iterable = this.iterable, body = _c326, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ForStaticItem");
        into.add_text(this.name);
        into.add(this.body.count);
        for (var _item326 in this.body) {
            _item326.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["iterable"] = this.iterable.to_json();
        var _v326 = JsonValue.array();
        for (var _item326 in this.body) {
            _v326.append(_item326.to_json());
        }
        out["body"] = _v326;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem::While`.
export struct WhileStaticItem {
    var condition: ast.Expression;
    var body: Array<StaticItem>;
    var loc: Loc;

    construct(condition: ast.Expression, body: Array<StaticItem> = Array<StaticItem>(), loc: Loc = Loc()) {
        this.condition = condition;
        this.body = body;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): WhileStaticItem {
        var _c330 = Array<StaticItem>();
        for (var _item330 in this.body) {
            _c330.append(_item330.copy());
        }
        return WhileStaticItem(condition = this.condition, body = _c330, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("WhileStaticItem");
        into.add(this.body.count);
        for (var _item330 in this.body) {
            _item330.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v330 = JsonValue.array();
        for (var _item330 in this.body) {
            _v330.append(_item330.to_json());
        }
        out["body"] = _v330;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem::Jump`.
export struct JumpStaticItem {
    var kind: LoopBreakKind;
    var loc: Loc;

    construct(kind: LoopBreakKind, loc: Loc = Loc()) {
        this.kind = kind;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): JumpStaticItem {
        return JumpStaticItem(kind = this.kind, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("JumpStaticItem");
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["kind"] = this.kind.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem::If`.
export struct IfStaticItem {
    var condition: ast.Expression;
    var then_items: Array<StaticItem>;
    var else_items: Array<StaticItem>;
    var loc: Loc;

    construct(
        condition: ast.Expression,
        then_items: Array<StaticItem> = Array<StaticItem>(),
        else_items: Array<StaticItem> = Array<StaticItem>(),
        loc: Loc = Loc()
    ) {
        this.condition = condition;
        this.then_items = then_items;
        this.else_items = else_items;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): IfStaticItem {
        var _c336 = Array<StaticItem>();
        for (var _item336 in this.then_items) {
            _c336.append(_item336.copy());
        }
        var _c338 = Array<StaticItem>();
        for (var _item338 in this.else_items) {
            _c338.append(_item338.copy());
        }
        return IfStaticItem(condition = this.condition, then_items = _c336, else_items = _c338, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("IfStaticItem");
        into.add(this.then_items.count);
        for (var _item336 in this.then_items) {
            _item336.fingerprint(into);
        }
        into.add(this.else_items.count);
        for (var _item338 in this.else_items) {
            _item338.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v336 = JsonValue.array();
        for (var _item336 in this.then_items) {
            _v336.append(_item336.to_json());
        }
        out["then_items"] = _v336;
        var _v338 = JsonValue.array();
        for (var _item338 in this.else_items) {
            _v338.append(_item338.to_json());
        }
        out["else_items"] = _v338;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem::EmitIf`.
export struct EmitIfStaticItem {
    var condition: Expression;
    var then_items: Array<StaticItem>;
    var else_items: Array<StaticItem>;
    var span: ast.Span;

    construct(
        condition: Expression,
        then_items: Array<StaticItem> = Array<StaticItem>(),
        else_items: Array<StaticItem> = Array<StaticItem>(),
        span: ast.Span = ast.Span()
    ) {
        this.condition = condition;
        this.then_items = then_items;
        this.else_items = else_items;
        this.span = span;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): EmitIfStaticItem {
        var _c342 = Array<StaticItem>();
        for (var _item342 in this.then_items) {
            _c342.append(_item342.copy());
        }
        var _c344 = Array<StaticItem>();
        for (var _item344 in this.else_items) {
            _c344.append(_item344.copy());
        }
        return EmitIfStaticItem(
            condition = this.condition.copy(), then_items = _c342, else_items = _c344, span = this.span
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("EmitIfStaticItem");
        this.condition.fingerprint(into);
        into.add(this.then_items.count);
        for (var _item342 in this.then_items) {
            _item342.fingerprint(into);
        }
        into.add(this.else_items.count);
        for (var _item344 in this.else_items) {
            _item344.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v342 = JsonValue.array();
        for (var _item342 in this.then_items) {
            _v342.append(_item342.to_json());
        }
        out["then_items"] = _v342;
        var _v344 = JsonValue.array();
        for (var _item344 in this.else_items) {
            _v344.append(_item344.to_json());
        }
        out["else_items"] = _v344;
        out["span"] = this.span.to_json();
        return out;
    }
}

## The fields of `StaticItem::Var`.
export struct VarStaticItem {
    var name: String;
    var value: ast.Expression;
    var loc: Loc;

    construct(value: ast.Expression, name: String = "", loc: Loc = Loc()) {
        this.value = value;
        this.name = name;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): VarStaticItem {
        return VarStaticItem(name = this.name, value = this.value, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("VarStaticItem");
        into.add_text(this.name);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["value"] = this.value.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `VariableDef` in `model.rs`.
export struct VariableDef {
    var name: String;
    var ty: TypeName;
    var default: Expression?;
    var hidden: bool;
    var kind: Kind;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;
    var type_loc: Loc;
    var is_const: bool;

    construct(
        name: String = "",
        ty: TypeName = TypeName(),
        default: Expression? = Optional<Expression>.Empty,
        hidden: bool = false,
        kind: Kind = Kind.Variable,
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc(),
        type_loc: Loc = Loc(),
        is_const: bool = false
    ) {
        this.name = name;
        this.ty = ty;
        this.default = default;
        this.hidden = hidden;
        this.kind = kind;
        this.attributes = attributes;
        this.loc = loc;
        this.type_loc = type_loc;
        this.is_const = is_const;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): VariableDef {
        var _c357 = Optional<Expression>.Empty;
        if (this.default.is_value()) {
            _c357 = Optional<Expression>.Value(this.default.value().copy());
        }
        return VariableDef(
            name = this.name,
            ty = this.ty.copy(),
            default = _c357,
            hidden = this.hidden,
            kind = this.kind,
            attributes = this.attributes.copy(),
            loc = this.loc,
            type_loc = this.type_loc,
            is_const = this.is_const
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("VariableDef");
        into.add_text(this.name);
        this.ty.fingerprint(into);
        if (this.default.is_value()) {
            this.default.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.hidden ? 1 : 0);
        this.kind.fingerprint(into);
        into.add(this.attributes.count);
        for (var _item361 in this.attributes) {}
        this.loc.fingerprint(into);
        this.type_loc.fingerprint(into);
        into.add(this.is_const ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        out["default"] = (this.default.is_value() ? this.default.value().to_json() : JsonValue.Null);
        out["hidden"] = JsonValue.Bool(this.hidden);
        out["kind"] = this.kind.to_json();
        var _v361 = JsonValue.array();
        for (var _item361 in this.attributes) {
            _v361.append(_item361.to_json());
        }
        out["attributes"] = _v361;
        out["loc"] = this.loc.to_json();
        out["type_loc"] = this.type_loc.to_json();
        out["is_const"] = JsonValue.Bool(this.is_const);
        return out;
    }
}

## `GenericParam` in `model.rs`.
export struct GenericParam {
    var name: String;
    var loc: Loc;
    var bounds: Array<Bound>;
    var default: TypeName?;
    var default_loc: Loc;
    var is_argument: bool;

    construct(
        name: String = "",
        loc: Loc = Loc(),
        bounds: Array<Bound> = Array<Bound>(),
        default: TypeName? = Optional<TypeName>.Empty,
        default_loc: Loc = Loc(),
        is_argument: bool = false
    ) {
        this.name = name;
        this.loc = loc;
        this.bounds = bounds;
        this.default = default;
        this.default_loc = default_loc;
        this.is_argument = is_argument;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): GenericParam {
        var _c368 = Array<Bound>();
        for (var _item368 in this.bounds) {
            _c368.append(_item368.copy());
        }
        var _c370 = Optional<TypeName>.Empty;
        if (this.default.is_value()) {
            _c370 = Optional<TypeName>.Value(this.default.value().copy());
        }
        return GenericParam(
            name = this.name,
            loc = this.loc,
            bounds = _c368,
            default = _c370,
            default_loc = this.default_loc,
            is_argument = this.is_argument
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("GenericParam");
        into.add_text(this.name);
        this.loc.fingerprint(into);
        into.add(this.bounds.count);
        for (var _item368 in this.bounds) {
            _item368.fingerprint(into);
        }
        if (this.default.is_value()) {
            this.default.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        this.default_loc.fingerprint(into);
        into.add(this.is_argument ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["loc"] = this.loc.to_json();
        var _v368 = JsonValue.array();
        for (var _item368 in this.bounds) {
            _v368.append(_item368.to_json());
        }
        out["bounds"] = _v368;
        out["default"] = (this.default.is_value() ? this.default.value().to_json() : JsonValue.Null);
        out["default_loc"] = this.default_loc.to_json();
        out["is_argument"] = JsonValue.Bool(this.is_argument);
        return out;
    }
}

## `Bound` in `model.rs`.
export struct Bound {
    var ty: TypeName;
    var loc: Loc;

    construct(ty: TypeName = TypeName(), loc: Loc = Loc()) {
        this.ty = ty;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Bound {
        return Bound(ty = this.ty.copy(), loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Bound");
        this.ty.fingerprint(into);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `Withheld` in `model.rs`.
export struct Withheld {
    var owner: String;
    var member: String;
    var name: String;
    var params: ulong;
    var arg: TypeName;
    var bound: TypeName;
    var at: Loc;

    construct(
        owner: String = "",
        member: String = "",
        name: String = "",
        params: ulong = 0,
        arg: TypeName = TypeName(),
        bound: TypeName = TypeName(),
        at: Loc = Loc()
    ) {
        this.owner = owner;
        this.member = member;
        this.name = name;
        this.params = params;
        this.arg = arg;
        this.bound = bound;
        this.at = at;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Withheld {
        return Withheld(
            owner = this.owner,
            member = this.member,
            name = this.name,
            params = this.params,
            arg = this.arg.copy(),
            bound = this.bound.copy(),
            at = this.at
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Withheld");
        into.add_text(this.owner);
        into.add_text(this.member);
        into.add_text(this.name);
        into.add(this.params as ulong);
        this.arg.fingerprint(into);
        this.bound.fingerprint(into);
        this.at.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["owner"] = JsonValue.String(this.owner);
        out["member"] = JsonValue.String(this.member);
        out["name"] = JsonValue.String(this.name);
        out["params"] = unsigned_json(this.params);
        out["arg"] = this.arg.to_json();
        out["bound"] = this.bound.to_json();
        out["at"] = this.at.to_json();
        return out;
    }
}

## `TypeUse` in `model.rs`.
export struct TypeUse {
    var ty: TypeName;
    var args: Array<Loc>;
    var context: ulong;

    construct(ty: TypeName = TypeName(), args: Array<Loc> = Array<Loc>(), context: ulong = 0) {
        this.ty = ty;
        this.args = args;
        this.context = context;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TypeUse {
        return TypeUse(ty = this.ty.copy(), args = this.args.copy(), context = this.context);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TypeUse");
        this.ty.fingerprint(into);
        into.add(this.args.count);
        for (var _item384 in this.args) {
            _item384.fingerprint(into);
        }
        into.add(this.context as ulong);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        var _v384 = JsonValue.array();
        for (var _item384 in this.args) {
            _v384.append(_item384.to_json());
        }
        out["args"] = _v384;
        out["context"] = unsigned_json(this.context);
        return out;
    }
}

## `UseContext` in `model.rs`.
export struct UseContext {
    var scope: Array<GenericParam>;
    var extension: TypeName?;
    var conditions: Array<ast.Attribute>;

    construct(
        scope: Array<GenericParam> = Array<GenericParam>(),
        extension: TypeName? = Optional<TypeName>.Empty,
        conditions: Array<ast.Attribute> = Array<ast.Attribute>()
    ) {
        this.scope = scope;
        this.extension = extension;
        this.conditions = conditions;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): UseContext {
        var _c387 = Array<GenericParam>();
        for (var _item387 in this.scope) {
            _c387.append(_item387.copy());
        }
        var _c389 = Optional<TypeName>.Empty;
        if (this.extension.is_value()) {
            _c389 = Optional<TypeName>.Value(this.extension.value().copy());
        }
        return UseContext(scope = _c387, extension = _c389, conditions = this.conditions.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("UseContext");
        into.add(this.scope.count);
        for (var _item387 in this.scope) {
            _item387.fingerprint(into);
        }
        if (this.extension.is_value()) {
            this.extension.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.conditions.count);
        for (var _item391 in this.conditions) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v387 = JsonValue.array();
        for (var _item387 in this.scope) {
            _v387.append(_item387.to_json());
        }
        out["scope"] = _v387;
        out["extension"] = (this.extension.is_value() ? this.extension.value().to_json() : JsonValue.Null);
        var _v391 = JsonValue.array();
        for (var _item391 in this.conditions) {
            _v391.append(_item391.to_json());
        }
        out["conditions"] = _v391;
        return out;
    }
}

## `FunctionDef` in `model.rs`.
export struct FunctionDef {
    var name: String;
    var ty: TypeName;
    var generic_params: Array<GenericParam>;
    var parameters: Array<VariableDef>;
    var body: Block?;
    var parent: String?;
    var is_static: bool;
    var is_indexer: bool;
    var is_generic_func: bool;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;
    var trait_default: Array<String>?;
    var owner: Loc;

    construct(
        name: String = "",
        ty: TypeName = TypeName(),
        generic_params: Array<GenericParam> = Array<GenericParam>(),
        parameters: Array<VariableDef> = Array<VariableDef>(),
        body: Block? = Optional<Block>.Empty,
        parent: String? = Optional<String>.Empty,
        is_static: bool = false,
        is_indexer: bool = false,
        is_generic_func: bool = false,
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc(),
        trait_default: Array<String>? = Optional<Array<String>>.Empty,
        owner: Loc = Loc()
    ) {
        this.name = name;
        this.ty = ty;
        this.generic_params = generic_params;
        this.parameters = parameters;
        this.body = body;
        this.parent = parent;
        this.is_static = is_static;
        this.is_indexer = is_indexer;
        this.is_generic_func = is_generic_func;
        this.attributes = attributes;
        this.loc = loc;
        this.trait_default = trait_default;
        this.owner = owner;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FunctionDef {
        var _c395 = Array<GenericParam>();
        for (var _item395 in this.generic_params) {
            _c395.append(_item395.copy());
        }
        var _c397 = Array<VariableDef>();
        for (var _item397 in this.parameters) {
            _c397.append(_item397.copy());
        }
        var _c399 = Optional<Block>.Empty;
        if (this.body.is_value()) {
            _c399 = Optional<Block>.Value(this.body.value().copy());
        }
        var _c409 = Optional<Array<String>>.Empty;
        if (this.trait_default.is_value()) {
            _c409 = Optional<Array<String>>.Value(this.trait_default.value().copy());
        }
        return FunctionDef(
            name = this.name,
            ty = this.ty.copy(),
            generic_params = _c395,
            parameters = _c397,
            body = _c399,
            parent = this.parent,
            is_static = this.is_static,
            is_indexer = this.is_indexer,
            is_generic_func = this.is_generic_func,
            attributes = this.attributes.copy(),
            loc = this.loc,
            trait_default = _c409,
            owner = this.owner
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionDef");
        into.add_text(this.name);
        this.ty.fingerprint(into);
        into.add(this.generic_params.count);
        for (var _item395 in this.generic_params) {
            _item395.fingerprint(into);
        }
        into.add(this.parameters.count);
        for (var _item397 in this.parameters) {
            _item397.fingerprint(into);
        }
        if (this.body.is_value()) {
            this.body.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        if (this.parent.is_value()) {
            into.add_text(this.parent.value());
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.is_static ? 1 : 0);
        into.add(this.is_indexer ? 1 : 0);
        into.add(this.is_generic_func ? 1 : 0);
        into.add(this.attributes.count);
        for (var _item406 in this.attributes) {}
        this.loc.fingerprint(into);
        if (this.trait_default.is_value()) {
            into.add(this.trait_default.value().count);
            for (var _item410 in this.trait_default.value()) {
                into.add_text(_item410);
            }
            into.add(1);
        } else {
            into.add(0);
        }
        this.owner.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        var _v395 = JsonValue.array();
        for (var _item395 in this.generic_params) {
            _v395.append(_item395.to_json());
        }
        out["generic_params"] = _v395;
        var _v397 = JsonValue.array();
        for (var _item397 in this.parameters) {
            _v397.append(_item397.to_json());
        }
        out["parameters"] = _v397;
        out["body"] = (this.body.is_value() ? this.body.value().to_json() : JsonValue.Null);
        out["parent"] = (this.parent.is_value() ? JsonValue.String(this.parent.value()) : JsonValue.Null);
        out["is_static"] = JsonValue.Bool(this.is_static);
        out["is_indexer"] = JsonValue.Bool(this.is_indexer);
        out["is_generic_func"] = JsonValue.Bool(this.is_generic_func);
        var _v406 = JsonValue.array();
        for (var _item406 in this.attributes) {
            _v406.append(_item406.to_json());
        }
        out["attributes"] = _v406;
        out["loc"] = this.loc.to_json();
        var _v409 = JsonValue.Null;
        if (this.trait_default.is_value()) {
            var _v410 = JsonValue.array();
            for (var _item410 in this.trait_default.value()) {
                _v410.append(JsonValue.String(_item410));
            }
            _v409 = _v410;
        }
        out["trait_default"] = _v409;
        out["owner"] = this.owner.to_json();
        return out;
    }
}

## `StructDef` in `model.rs`.
export struct StructDef {
    var name: String;
    var ty: TypeName;
    var generic_params: Array<GenericParam>;
    var field_members: Array<VariableDef>;
    var method_members: Array<FunctionDef>;
    var generic_methods: Array<FunctionDef>;
    var constructors: Array<FunctionDef>;
    var destructor: FunctionDef;
    var acquire: FunctionDef;
    var release: FunctionDef;
    var traits: Array<TypeName>;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;
    var enum_cases: Array<EnumCaseDef>?;

    construct(
        name: String = "",
        ty: TypeName = TypeName(),
        generic_params: Array<GenericParam> = Array<GenericParam>(),
        field_members: Array<VariableDef> = Array<VariableDef>(),
        method_members: Array<FunctionDef> = Array<FunctionDef>(),
        generic_methods: Array<FunctionDef> = Array<FunctionDef>(),
        constructors: Array<FunctionDef> = Array<FunctionDef>(),
        destructor: FunctionDef = FunctionDef(),
        acquire: FunctionDef = FunctionDef(),
        release: FunctionDef = FunctionDef(),
        traits: Array<TypeName> = Array<TypeName>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc(),
        enum_cases: Array<EnumCaseDef>? = Optional<Array<EnumCaseDef>>.Empty
    ) {
        this.name = name;
        this.ty = ty;
        this.generic_params = generic_params;
        this.field_members = field_members;
        this.method_members = method_members;
        this.generic_methods = generic_methods;
        this.constructors = constructors;
        this.destructor = destructor;
        this.acquire = acquire;
        this.release = release;
        this.traits = traits;
        this.attributes = attributes;
        this.loc = loc;
        this.enum_cases = enum_cases;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): StructDef {
        var _c415 = Array<GenericParam>();
        for (var _item415 in this.generic_params) {
            _c415.append(_item415.copy());
        }
        var _c417 = Array<VariableDef>();
        for (var _item417 in this.field_members) {
            _c417.append(_item417.copy());
        }
        var _c419 = Array<FunctionDef>();
        for (var _item419 in this.method_members) {
            _c419.append(_item419.copy());
        }
        var _c421 = Array<FunctionDef>();
        for (var _item421 in this.generic_methods) {
            _c421.append(_item421.copy());
        }
        var _c423 = Array<FunctionDef>();
        for (var _item423 in this.constructors) {
            _c423.append(_item423.copy());
        }
        var _c428 = Array<TypeName>();
        for (var _item428 in this.traits) {
            _c428.append(_item428.copy());
        }
        var _c433 = Optional<Array<EnumCaseDef>>.Empty;
        if (this.enum_cases.is_value()) {
            var _c434 = Array<EnumCaseDef>();
            for (var _item434 in this.enum_cases.value()) {
                _c434.append(_item434.copy());
            }
            _c433 = Optional<Array<EnumCaseDef>>.Value(_c434);
        }
        return StructDef(
            name = this.name,
            ty = this.ty.copy(),
            generic_params = _c415,
            field_members = _c417,
            method_members = _c419,
            generic_methods = _c421,
            constructors = _c423,
            destructor = this.destructor.copy(),
            acquire = this.acquire.copy(),
            release = this.release.copy(),
            traits = _c428,
            attributes = this.attributes.copy(),
            loc = this.loc,
            enum_cases = _c433
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StructDef");
        into.add_text(this.name);
        this.ty.fingerprint(into);
        into.add(this.generic_params.count);
        for (var _item415 in this.generic_params) {
            _item415.fingerprint(into);
        }
        into.add(this.field_members.count);
        for (var _item417 in this.field_members) {
            _item417.fingerprint(into);
        }
        into.add(this.method_members.count);
        for (var _item419 in this.method_members) {
            _item419.fingerprint(into);
        }
        into.add(this.generic_methods.count);
        for (var _item421 in this.generic_methods) {
            _item421.fingerprint(into);
        }
        into.add(this.constructors.count);
        for (var _item423 in this.constructors) {
            _item423.fingerprint(into);
        }
        this.destructor.fingerprint(into);
        this.acquire.fingerprint(into);
        this.release.fingerprint(into);
        into.add(this.traits.count);
        for (var _item428 in this.traits) {
            _item428.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item430 in this.attributes) {}
        this.loc.fingerprint(into);
        if (this.enum_cases.is_value()) {
            into.add(this.enum_cases.value().count);
            for (var _item434 in this.enum_cases.value()) {
                _item434.fingerprint(into);
            }
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        var _v415 = JsonValue.array();
        for (var _item415 in this.generic_params) {
            _v415.append(_item415.to_json());
        }
        out["generic_params"] = _v415;
        var _v417 = JsonValue.array();
        for (var _item417 in this.field_members) {
            _v417.append(_item417.to_json());
        }
        out["field_members"] = _v417;
        var _v419 = JsonValue.array();
        for (var _item419 in this.method_members) {
            _v419.append(_item419.to_json());
        }
        out["method_members"] = _v419;
        var _v421 = JsonValue.array();
        for (var _item421 in this.generic_methods) {
            _v421.append(_item421.to_json());
        }
        out["generic_methods"] = _v421;
        var _v423 = JsonValue.array();
        for (var _item423 in this.constructors) {
            _v423.append(_item423.to_json());
        }
        out["constructors"] = _v423;
        out["destructor"] = this.destructor.to_json();
        out["acquire"] = this.acquire.to_json();
        out["release"] = this.release.to_json();
        var _v428 = JsonValue.array();
        for (var _item428 in this.traits) {
            _v428.append(_item428.to_json());
        }
        out["traits"] = _v428;
        var _v430 = JsonValue.array();
        for (var _item430 in this.attributes) {
            _v430.append(_item430.to_json());
        }
        out["attributes"] = _v430;
        out["loc"] = this.loc.to_json();
        var _v433 = JsonValue.Null;
        if (this.enum_cases.is_value()) {
            var _v434 = JsonValue.array();
            for (var _item434 in this.enum_cases.value()) {
                _v434.append(_item434.to_json());
            }
            _v433 = _v434;
        }
        out["enum_cases"] = _v433;
        return out;
    }
}

## `AccessorKind` in `model.rs`.
export enum AccessorKind {
    Default,
    Body,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Default => {
                into.add(0);
            }
            Body => {
                into.add(1);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Default => {
                return JsonValue.String("Default");
            }
            Body => {
                return JsonValue.String("Body");
            }
        }
    }
}

## `PropertyDef` in `model.rs`.
export struct PropertyDef {
    var name: String;
    var owner: String;
    var in_trait: bool;
    var loc: Loc;
    var get: AccessorKind;
    var set: AccessorKind?;
    var set_loc: Loc;
    var storage: String?;
    var shared: bool;

    construct(
        name: String = "",
        owner: String = "",
        in_trait: bool = false,
        loc: Loc = Loc(),
        get: AccessorKind = AccessorKind.Default,
        set: AccessorKind? = Optional<AccessorKind>.Empty,
        set_loc: Loc = Loc(),
        storage: String? = Optional<String>.Empty,
        shared: bool = false
    ) {
        this.name = name;
        this.owner = owner;
        this.in_trait = in_trait;
        this.loc = loc;
        this.get = get;
        this.set = set;
        this.set_loc = set_loc;
        this.storage = storage;
        this.shared = shared;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): PropertyDef {
        return PropertyDef(
            name = this.name,
            owner = this.owner,
            in_trait = this.in_trait,
            loc = this.loc,
            get = this.get,
            set = this.set,
            set_loc = this.set_loc,
            storage = this.storage,
            shared = this.shared
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("PropertyDef");
        into.add_text(this.name);
        into.add_text(this.owner);
        into.add(this.in_trait ? 1 : 0);
        this.loc.fingerprint(into);
        this.get.fingerprint(into);
        if (this.set.is_value()) {
            this.set.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        this.set_loc.fingerprint(into);
        if (this.storage.is_value()) {
            into.add_text(this.storage.value());
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.shared ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["owner"] = JsonValue.String(this.owner);
        out["in_trait"] = JsonValue.Bool(this.in_trait);
        out["loc"] = this.loc.to_json();
        out["get"] = this.get.to_json();
        out["set"] = (this.set.is_value() ? this.set.value().to_json() : JsonValue.Null);
        out["set_loc"] = this.set_loc.to_json();
        out["storage"] = (this.storage.is_value() ? JsonValue.String(this.storage.value()) : JsonValue.Null);
        out["shared"] = JsonValue.Bool(this.shared);
        return out;
    }
}

## `Conversion` in `model.rs`.
export struct Conversion {
    var at: Loc;
    var from: TypeName;
    var to: TypeName;
    var constructor: Loc;

    construct(at: Loc = Loc(), from: TypeName = TypeName(), to: TypeName = TypeName(), constructor: Loc = Loc()) {
        this.at = at;
        this.from = from;
        this.to = to;
        this.constructor = constructor;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Conversion {
        return Conversion(at = this.at, from = this.from.copy(), to = this.to.copy(), constructor = this.constructor);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Conversion");
        this.at.fingerprint(into);
        this.from.fingerprint(into);
        this.to.fingerprint(into);
        this.constructor.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["at"] = this.at.to_json();
        out["from"] = this.from.to_json();
        out["to"] = this.to.to_json();
        out["constructor"] = this.constructor.to_json();
        return out;
    }
}

## `TraitDef` in `model.rs`.
export struct TraitDef {
    var name: String;
    var generic_params: Array<GenericParam>;
    var methods: Array<FunctionDef>;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;

    construct(
        name: String = "",
        generic_params: Array<GenericParam> = Array<GenericParam>(),
        methods: Array<FunctionDef> = Array<FunctionDef>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc()
    ) {
        this.name = name;
        this.generic_params = generic_params;
        this.methods = methods;
        this.attributes = attributes;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TraitDef {
        var _c452 = Array<GenericParam>();
        for (var _item452 in this.generic_params) {
            _c452.append(_item452.copy());
        }
        var _c454 = Array<FunctionDef>();
        for (var _item454 in this.methods) {
            _c454.append(_item454.copy());
        }
        return TraitDef(
            name = this.name,
            generic_params = _c452,
            methods = _c454,
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TraitDef");
        into.add_text(this.name);
        into.add(this.generic_params.count);
        for (var _item452 in this.generic_params) {
            _item452.fingerprint(into);
        }
        into.add(this.methods.count);
        for (var _item454 in this.methods) {
            _item454.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item456 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v452 = JsonValue.array();
        for (var _item452 in this.generic_params) {
            _v452.append(_item452.to_json());
        }
        out["generic_params"] = _v452;
        var _v454 = JsonValue.array();
        for (var _item454 in this.methods) {
            _v454.append(_item454.to_json());
        }
        out["methods"] = _v454;
        var _v456 = JsonValue.array();
        for (var _item456 in this.attributes) {
            _v456.append(_item456.to_json());
        }
        out["attributes"] = _v456;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `TraitType` in `model.rs`.
export struct TraitType {
    var ty: TypeName;
    var methods: Array<FunctionDef>;

    construct(ty: TypeName = TypeName(), methods: Array<FunctionDef> = Array<FunctionDef>()) {
        this.ty = ty;
        this.methods = methods;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TraitType {
        var _c460 = Array<FunctionDef>();
        for (var _item460 in this.methods) {
            _c460.append(_item460.copy());
        }
        return TraitType(ty = this.ty.copy(), methods = _c460);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TraitType");
        this.ty.fingerprint(into);
        into.add(this.methods.count);
        for (var _item460 in this.methods) {
            _item460.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        var _v460 = JsonValue.array();
        for (var _item460 in this.methods) {
            _v460.append(_item460.to_json());
        }
        out["methods"] = _v460;
        return out;
    }
}

## `ExtensionDef` in `model.rs`.
export struct ExtensionDef {
    var target: TypeName;
    var resolved: String?;
    var traits: Array<TypeName>;
    var restated: Array<(ulong, Bound)>;
    var methods: Array<FunctionDef>;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;
    var is_exported: bool;
    var is_private: bool;

    construct(
        target: TypeName = TypeName(),
        resolved: String? = Optional<String>.Empty,
        traits: Array<TypeName> = Array<TypeName>(),
        restated: Array<(ulong, Bound)> = Array<(ulong, Bound)>(),
        methods: Array<FunctionDef> = Array<FunctionDef>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc(),
        is_exported: bool = false,
        is_private: bool = false
    ) {
        this.target = target;
        this.resolved = resolved;
        this.traits = traits;
        this.restated = restated;
        this.methods = methods;
        this.attributes = attributes;
        this.loc = loc;
        this.is_exported = is_exported;
        this.is_private = is_private;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ExtensionDef {
        var _c465 = Array<TypeName>();
        for (var _item465 in this.traits) {
            _c465.append(_item465.copy());
        }
        var _c467 = Array<(ulong, Bound)>();
        for (var _item467 in this.restated) {
            var (_t468_0, _t468_1) = _item467;
            _c467.append((_t468_0, _t468_1.copy()));
        }
        var _c471 = Array<FunctionDef>();
        for (var _item471 in this.methods) {
            _c471.append(_item471.copy());
        }
        return ExtensionDef(
            target = this.target.copy(),
            resolved = this.resolved,
            traits = _c465,
            restated = _c467,
            methods = _c471,
            attributes = this.attributes.copy(),
            loc = this.loc,
            is_exported = this.is_exported,
            is_private = this.is_private
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ExtensionDef");
        this.target.fingerprint(into);
        if (this.resolved.is_value()) {
            into.add_text(this.resolved.value());
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.traits.count);
        for (var _item465 in this.traits) {
            _item465.fingerprint(into);
        }
        into.add(this.restated.count);
        for (var _item467 in this.restated) {
            var (_t468_0, _t468_1) = _item467;
            into.add(_t468_0 as ulong);
            _t468_1.fingerprint(into);
        }
        into.add(this.methods.count);
        for (var _item471 in this.methods) {
            _item471.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item473 in this.attributes) {}
        this.loc.fingerprint(into);
        into.add(this.is_exported ? 1 : 0);
        into.add(this.is_private ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["target"] = this.target.to_json();
        out["resolved"] = (this.resolved.is_value() ? JsonValue.String(this.resolved.value()) : JsonValue.Null);
        var _v465 = JsonValue.array();
        for (var _item465 in this.traits) {
            _v465.append(_item465.to_json());
        }
        out["traits"] = _v465;
        var _v467 = JsonValue.array();
        for (var _item467 in this.restated) {
            var _v468 = JsonValue.array();
            var _t468 = _item467;
            var (_t468_0, _t468_1) = _t468;
            _v468.append(unsigned_json(_t468_0));
            _v468.append(_t468_1.to_json());
            _v467.append(_v468);
        }
        out["restated"] = _v467;
        var _v471 = JsonValue.array();
        for (var _item471 in this.methods) {
            _v471.append(_item471.to_json());
        }
        out["methods"] = _v471;
        var _v473 = JsonValue.array();
        for (var _item473 in this.attributes) {
            _v473.append(_item473.to_json());
        }
        out["attributes"] = _v473;
        out["loc"] = this.loc.to_json();
        out["is_exported"] = JsonValue.Bool(this.is_exported);
        out["is_private"] = JsonValue.Bool(this.is_private);
        return out;
    }
}

## `ExtensionScopes` in `model.rs`.
export struct ExtensionScopes {
    var prelude: HashSet<uint>;
    var visible: Array<HashSet<uint>>;
    var module: Array<Optional<uint>>;

    construct(
        prelude: HashSet<uint> = HashSet<uint>(),
        visible: Array<HashSet<uint>> = Array<HashSet<uint>>(),
        module: Array<Optional<uint>> = Array<Optional<uint>>()
    ) {
        this.prelude = prelude;
        this.visible = visible;
        this.module = module;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ExtensionScopes {
        var _c480 = Array<HashSet<uint>>();
        for (var _item480 in this.visible) {
            _c480.append(_item480.copy());
        }
        return ExtensionScopes(prelude = this.prelude.copy(), visible = _c480, module = this.module.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ExtensionScopes");
        into.add(this.prelude.count);
        for (var _item478 in this.prelude) {
            into.add(_item478 as ulong);
        }
        into.add(this.visible.count);
        for (var _item480 in this.visible) {
            into.add(_item480.count);
            for (var _item481 in _item480) {
                into.add(_item481 as ulong);
            }
        }
        into.add(this.module.count);
        for (var _item483 in this.module) {
            if (_item483.is_value()) {
                into.add(_item483.value() as ulong);
                into.add(1);
            } else {
                into.add(0);
            }
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v478 = JsonValue.array();
        for (var _item478 in this.prelude) {
            _v478.append(JsonValue.Integer(_item478 as long));
        }
        out["prelude"] = _v478;
        var _v480 = JsonValue.array();
        for (var _item480 in this.visible) {
            var _v481 = JsonValue.array();
            for (var _item481 in _item480) {
                _v481.append(JsonValue.Integer(_item481 as long));
            }
            _v480.append(_v481);
        }
        out["visible"] = _v480;
        var _v483 = JsonValue.array();
        for (var _item483 in this.module) {
            _v483.append((_item483.is_value() ? JsonValue.Integer(_item483.value() as long) : JsonValue.Null));
        }
        out["module"] = _v483;
        return out;
    }
}

## `ExternDef` in `model.rs`.
export struct ExternDef {
    var name: String;
    var ty: TypeName;
    var parameters: Array<VariableDef>;
    var is_variadic: bool;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;

    construct(
        name: String = "",
        ty: TypeName = TypeName(),
        parameters: Array<VariableDef> = Array<VariableDef>(),
        is_variadic: bool = false,
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc()
    ) {
        this.name = name;
        this.ty = ty;
        this.parameters = parameters;
        this.is_variadic = is_variadic;
        this.attributes = attributes;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ExternDef {
        var _c488 = Array<VariableDef>();
        for (var _item488 in this.parameters) {
            _c488.append(_item488.copy());
        }
        return ExternDef(
            name = this.name,
            ty = this.ty.copy(),
            parameters = _c488,
            is_variadic = this.is_variadic,
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ExternDef");
        into.add_text(this.name);
        this.ty.fingerprint(into);
        into.add(this.parameters.count);
        for (var _item488 in this.parameters) {
            _item488.fingerprint(into);
        }
        into.add(this.is_variadic ? 1 : 0);
        into.add(this.attributes.count);
        for (var _item491 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        var _v488 = JsonValue.array();
        for (var _item488 in this.parameters) {
            _v488.append(_item488.to_json());
        }
        out["parameters"] = _v488;
        out["is_variadic"] = JsonValue.Bool(this.is_variadic);
        var _v491 = JsonValue.array();
        for (var _item491 in this.attributes) {
            _v491.append(_item491.to_json());
        }
        out["attributes"] = _v491;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `TypeAliasDef` in `model.rs`.
export struct TypeAliasDef {
    var name: String;
    var generic_params: Array<GenericParam>;
    var target: TypeName;
    var attributes: Array<ast.Attribute>;
    var loc: Loc;

    construct(
        name: String = "",
        generic_params: Array<GenericParam> = Array<GenericParam>(),
        target: TypeName = TypeName(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc()
    ) {
        this.name = name;
        this.generic_params = generic_params;
        this.target = target;
        this.attributes = attributes;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TypeAliasDef {
        var _c495 = Array<GenericParam>();
        for (var _item495 in this.generic_params) {
            _c495.append(_item495.copy());
        }
        return TypeAliasDef(
            name = this.name,
            generic_params = _c495,
            target = this.target.copy(),
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TypeAliasDef");
        into.add_text(this.name);
        into.add(this.generic_params.count);
        for (var _item495 in this.generic_params) {
            _item495.fingerprint(into);
        }
        this.target.fingerprint(into);
        into.add(this.attributes.count);
        for (var _item498 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v495 = JsonValue.array();
        for (var _item495 in this.generic_params) {
            _v495.append(_item495.to_json());
        }
        out["generic_params"] = _v495;
        out["target"] = this.target.to_json();
        var _v498 = JsonValue.array();
        for (var _item498 in this.attributes) {
            _v498.append(_item498.to_json());
        }
        out["attributes"] = _v498;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `Declaration` in `model.rs`.
export enum Declaration {
    Variable(value: VariableDef),
    Function(value: FunctionDef),
    Struct(value: StructDef),
    Trait(value: TraitDef),
    Extension(value: ExtensionDef),
    Extern(value: ExternDef),
    TypeAlias(value: TypeAliasDef),

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Variable(value) => {
                into.add(0);
                value.fingerprint(into);
            }
            Function(value) => {
                into.add(1);
                value.fingerprint(into);
            }
            Struct(value) => {
                into.add(2);
                value.fingerprint(into);
            }
            Trait(value) => {
                into.add(3);
                value.fingerprint(into);
            }
            Extension(value) => {
                into.add(4);
                value.fingerprint(into);
            }
            Extern(value) => {
                into.add(5);
                value.fingerprint(into);
            }
            TypeAlias(value) => {
                into.add(6);
                value.fingerprint(into);
            }
        }
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Declaration {
        match (this) {
            Variable(value) => {
                return Declaration.Variable(value.copy());
            }
            Function(value) => {
                return Declaration.Function(value.copy());
            }
            Struct(value) => {
                return Declaration.Struct(value.copy());
            }
            Trait(value) => {
                return Declaration.Trait(value.copy());
            }
            Extension(value) => {
                return Declaration.Extension(value.copy());
            }
            Extern(value) => {
                return Declaration.Extern(value.copy());
            }
            TypeAlias(value) => {
                return Declaration.TypeAlias(value.copy());
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Variable(value) => {
                return _tagged("Variable", value.to_json());
            }
            Function(value) => {
                return _tagged("Function", value.to_json());
            }
            Struct(value) => {
                return _tagged("Struct", value.to_json());
            }
            Trait(value) => {
                return _tagged("Trait", value.to_json());
            }
            Extension(value) => {
                return _tagged("Extension", value.to_json());
            }
            Extern(value) => {
                return _tagged("Extern", value.to_json());
            }
            TypeAlias(value) => {
                return _tagged("TypeAlias", value.to_json());
            }
        }
    }
}

## `Module` in `model.rs`.
export struct Module {
    var imports: Array<ast.Import>;
    var structs: Array<StructDef>;
    var traits: Array<TraitDef>;
    var extensions: Array<ExtensionDef>;
    var functions: Array<FunctionDef>;
    var externs: Array<ExternDef>;
    var globals: Array<VariableDef>;
    var static_blocks: Array<ModuleStaticBlock>;
    var enums: Array<EnumDef>;
    var struct_specs: Array<TypeName>;
    var func_specs: Array<TypeName>;
    var type_aliases: Array<TypeAliasDef>;
    var withheld: Array<Withheld>;
    var properties: Array<PropertyDef>;
    var type_uses: Array<TypeUse>;
    var use_contexts: Array<UseContext>;
    var literal_args: Array<(Loc, ulong, Loc)>;
    var constrained_aliases: Array<TypeAliasDef>;
    var trait_types: Array<TraitType>;
    var conversions: Array<Conversion>;
    var overload_sets: Map<String, Array<String>>;
    var overload_unions: Map<String, Array<Array<String>>>;
    var method_overload_sets: Map<String, Map<String, Array<String>>>;
    var extension_scopes: ExtensionScopes;
    var private_functions: HashSet<Loc>;
    var file_private_functions: HashSet<Loc>;
    var call_targets: Array<(Loc, String)>;
    var argument_names: Array<(Loc, String)>;
    var namespaces: Array<String>;
    var cached_files: Array<bool>;
    var recorded_summaries: HashMap<Loc, String>;
    var stripped: HashSet<Loc>;
    var templates: Templates;
    var checked: Checked;
    var spec_requests: HashMap<String, SpecRequest>;
    var record_summaries: bool;
    var summaries_to_record: Array<(Loc, String)>;
    var caller_copies: HashMap<String, Array<bool>>;
    var linked: bool;

    construct(
        imports: Array<ast.Import> = Array<ast.Import>(),
        structs: Array<StructDef> = Array<StructDef>(),
        traits: Array<TraitDef> = Array<TraitDef>(),
        extensions: Array<ExtensionDef> = Array<ExtensionDef>(),
        functions: Array<FunctionDef> = Array<FunctionDef>(),
        externs: Array<ExternDef> = Array<ExternDef>(),
        globals: Array<VariableDef> = Array<VariableDef>(),
        static_blocks: Array<ModuleStaticBlock> = Array<ModuleStaticBlock>(),
        enums: Array<EnumDef> = Array<EnumDef>(),
        struct_specs: Array<TypeName> = Array<TypeName>(),
        func_specs: Array<TypeName> = Array<TypeName>(),
        type_aliases: Array<TypeAliasDef> = Array<TypeAliasDef>(),
        withheld: Array<Withheld> = Array<Withheld>(),
        properties: Array<PropertyDef> = Array<PropertyDef>(),
        type_uses: Array<TypeUse> = Array<TypeUse>(),
        use_contexts: Array<UseContext> = Array<UseContext>(),
        literal_args: Array<(Loc, ulong, Loc)> = Array<(Loc, ulong, Loc)>(),
        constrained_aliases: Array<TypeAliasDef> = Array<TypeAliasDef>(),
        trait_types: Array<TraitType> = Array<TraitType>(),
        conversions: Array<Conversion> = Array<Conversion>(),
        overload_sets: Map<String, Array<String>> = Map<String, Array<String>>(),
        overload_unions: Map<String, Array<Array<String>>> = Map<String, Array<Array<String>>>(),
        method_overload_sets: Map<String, Map<String, Array<String>>> = Map<String, Map<String, Array<String>>>(),
        extension_scopes: ExtensionScopes = ExtensionScopes(),
        private_functions: HashSet<Loc> = HashSet<Loc>(),
        file_private_functions: HashSet<Loc> = HashSet<Loc>(),
        call_targets: Array<(Loc, String)> = Array<(Loc, String)>(),
        argument_names: Array<(Loc, String)> = Array<(Loc, String)>(),
        namespaces: Array<String> = Array<String>(),
        cached_files: Array<bool> = Array<bool>(),
        recorded_summaries: HashMap<Loc, String> = HashMap<Loc, String>(),
        stripped: HashSet<Loc> = HashSet<Loc>(),
        templates: Templates = Templates(),
        checked: Checked = Checked(),
        spec_requests: HashMap<String, SpecRequest> = HashMap<String, SpecRequest>(),
        record_summaries: bool = false,
        summaries_to_record: Array<(Loc, String)> = Array<(Loc, String)>(),
        caller_copies: HashMap<String, Array<bool>> = HashMap<String, Array<bool>>(),
        linked: bool = false
    ) {
        this.imports = imports;
        this.structs = structs;
        this.traits = traits;
        this.extensions = extensions;
        this.functions = functions;
        this.externs = externs;
        this.globals = globals;
        this.static_blocks = static_blocks;
        this.enums = enums;
        this.struct_specs = struct_specs;
        this.func_specs = func_specs;
        this.type_aliases = type_aliases;
        this.withheld = withheld;
        this.properties = properties;
        this.type_uses = type_uses;
        this.use_contexts = use_contexts;
        this.literal_args = literal_args;
        this.constrained_aliases = constrained_aliases;
        this.trait_types = trait_types;
        this.conversions = conversions;
        this.overload_sets = overload_sets;
        this.overload_unions = overload_unions;
        this.method_overload_sets = method_overload_sets;
        this.extension_scopes = extension_scopes;
        this.private_functions = private_functions;
        this.file_private_functions = file_private_functions;
        this.call_targets = call_targets;
        this.argument_names = argument_names;
        this.namespaces = namespaces;
        this.cached_files = cached_files;
        this.recorded_summaries = recorded_summaries;
        this.stripped = stripped;
        this.templates = templates;
        this.checked = checked;
        this.spec_requests = spec_requests;
        this.record_summaries = record_summaries;
        this.summaries_to_record = summaries_to_record;
        this.caller_copies = caller_copies;
        this.linked = linked;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Module {
        var _c510 = Array<StructDef>();
        for (var _item510 in this.structs) {
            _c510.append(_item510.copy());
        }
        var _c512 = Array<TraitDef>();
        for (var _item512 in this.traits) {
            _c512.append(_item512.copy());
        }
        var _c514 = Array<ExtensionDef>();
        for (var _item514 in this.extensions) {
            _c514.append(_item514.copy());
        }
        var _c516 = Array<FunctionDef>();
        for (var _item516 in this.functions) {
            _c516.append(_item516.copy());
        }
        var _c518 = Array<ExternDef>();
        for (var _item518 in this.externs) {
            _c518.append(_item518.copy());
        }
        var _c520 = Array<VariableDef>();
        for (var _item520 in this.globals) {
            _c520.append(_item520.copy());
        }
        var _c522 = Array<ModuleStaticBlock>();
        for (var _item522 in this.static_blocks) {
            _c522.append(_item522.copy());
        }
        var _c524 = Array<EnumDef>();
        for (var _item524 in this.enums) {
            _c524.append(_item524.copy());
        }
        var _c526 = Array<TypeName>();
        for (var _item526 in this.struct_specs) {
            _c526.append(_item526.copy());
        }
        var _c528 = Array<TypeName>();
        for (var _item528 in this.func_specs) {
            _c528.append(_item528.copy());
        }
        var _c530 = Array<TypeAliasDef>();
        for (var _item530 in this.type_aliases) {
            _c530.append(_item530.copy());
        }
        var _c532 = Array<Withheld>();
        for (var _item532 in this.withheld) {
            _c532.append(_item532.copy());
        }
        var _c534 = Array<PropertyDef>();
        for (var _item534 in this.properties) {
            _c534.append(_item534.copy());
        }
        var _c536 = Array<TypeUse>();
        for (var _item536 in this.type_uses) {
            _c536.append(_item536.copy());
        }
        var _c538 = Array<UseContext>();
        for (var _item538 in this.use_contexts) {
            _c538.append(_item538.copy());
        }
        var _c540 = Array<(Loc, ulong, Loc)>();
        for (var _item540 in this.literal_args) {
            var (_t541_0, _t541_1, _t541_2) = _item540;
            _c540.append((_t541_0, _t541_1, _t541_2));
        }
        var _c545 = Array<TypeAliasDef>();
        for (var _item545 in this.constrained_aliases) {
            _c545.append(_item545.copy());
        }
        var _c547 = Array<TraitType>();
        for (var _item547 in this.trait_types) {
            _c547.append(_item547.copy());
        }
        var _c549 = Array<Conversion>();
        for (var _item549 in this.conversions) {
            _c549.append(_item549.copy());
        }
        var _c551 = Map<String, Array<String>>();
        for (var (_key551, _item551) in this.overload_sets) {
            _c551[_key551] = _item551.copy();
        }
        var _c554 = Map<String, Array<Array<String>>>();
        for (var (_key554, _item554) in this.overload_unions) {
            var _c555 = Array<Array<String>>();
            for (var _item555 in _item554) {
                _c555.append(_item555.copy());
            }
            _c554[_key554] = _c555;
        }
        var _c558 = Map<String, Map<String, Array<String>>>();
        for (var (_key558, _item558) in this.method_overload_sets) {
            var _c559 = Map<String, Array<String>>();
            for (var (_key559, _item559) in _item558) {
                _c559[_key559] = _item559.copy();
            }
            _c558[_key558] = _c559;
        }
        var _c567 = Array<(Loc, String)>();
        for (var _item567 in this.call_targets) {
            var (_t568_0, _t568_1) = _item567;
            _c567.append((_t568_0, _t568_1));
        }
        var _c571 = Array<(Loc, String)>();
        for (var _item571 in this.argument_names) {
            var (_t572_0, _t572_1) = _item571;
            _c571.append((_t572_0, _t572_1));
        }
        var _c579 = HashMap<Loc, String>();
        for (var (_key579, _item579) in this.recorded_summaries) {
            _c579[_key579] = _item579;
        }
        var _c585 = HashMap<String, SpecRequest>();
        for (var (_key585, _item585) in this.spec_requests) {
            _c585[_key585] = _item585.copy();
        }
        var _c588 = Array<(Loc, String)>();
        for (var _item588 in this.summaries_to_record) {
            var (_t589_0, _t589_1) = _item588;
            _c588.append((_t589_0, _t589_1));
        }
        var _c592 = HashMap<String, Array<bool>>();
        for (var (_key592, _item592) in this.caller_copies) {
            _c592[_key592] = _item592.copy();
        }
        return Module(
            imports = this.imports.copy(),
            structs = _c510,
            traits = _c512,
            extensions = _c514,
            functions = _c516,
            externs = _c518,
            globals = _c520,
            static_blocks = _c522,
            enums = _c524,
            struct_specs = _c526,
            func_specs = _c528,
            type_aliases = _c530,
            withheld = _c532,
            properties = _c534,
            type_uses = _c536,
            use_contexts = _c538,
            literal_args = _c540,
            constrained_aliases = _c545,
            trait_types = _c547,
            conversions = _c549,
            overload_sets = _c551,
            overload_unions = _c554,
            method_overload_sets = _c558,
            extension_scopes = this.extension_scopes.copy(),
            private_functions = this.private_functions.copy(),
            file_private_functions = this.file_private_functions.copy(),
            call_targets = _c567,
            argument_names = _c571,
            namespaces = this.namespaces.copy(),
            cached_files = this.cached_files.copy(),
            recorded_summaries = _c579,
            stripped = this.stripped.copy(),
            templates = this.templates.copy(),
            checked = this.checked.copy(),
            spec_requests = _c585,
            record_summaries = this.record_summaries,
            summaries_to_record = _c588,
            caller_copies = _c592,
            linked = this.linked
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Module");
        into.add(this.imports.count);
        for (var _item508 in this.imports) {}
        into.add(this.structs.count);
        for (var _item510 in this.structs) {
            _item510.fingerprint(into);
        }
        into.add(this.traits.count);
        for (var _item512 in this.traits) {
            _item512.fingerprint(into);
        }
        into.add(this.extensions.count);
        for (var _item514 in this.extensions) {
            _item514.fingerprint(into);
        }
        into.add(this.functions.count);
        for (var _item516 in this.functions) {
            _item516.fingerprint(into);
        }
        into.add(this.externs.count);
        for (var _item518 in this.externs) {
            _item518.fingerprint(into);
        }
        into.add(this.globals.count);
        for (var _item520 in this.globals) {
            _item520.fingerprint(into);
        }
        into.add(this.static_blocks.count);
        for (var _item522 in this.static_blocks) {
            _item522.fingerprint(into);
        }
        into.add(this.enums.count);
        for (var _item524 in this.enums) {
            _item524.fingerprint(into);
        }
        into.add(this.struct_specs.count);
        for (var _item526 in this.struct_specs) {
            _item526.fingerprint(into);
        }
        into.add(this.func_specs.count);
        for (var _item528 in this.func_specs) {
            _item528.fingerprint(into);
        }
        into.add(this.type_aliases.count);
        for (var _item530 in this.type_aliases) {
            _item530.fingerprint(into);
        }
        into.add(this.withheld.count);
        for (var _item532 in this.withheld) {
            _item532.fingerprint(into);
        }
        into.add(this.properties.count);
        for (var _item534 in this.properties) {
            _item534.fingerprint(into);
        }
        into.add(this.type_uses.count);
        for (var _item536 in this.type_uses) {
            _item536.fingerprint(into);
        }
        into.add(this.use_contexts.count);
        for (var _item538 in this.use_contexts) {
            _item538.fingerprint(into);
        }
        into.add(this.literal_args.count);
        for (var _item540 in this.literal_args) {
            var (_t541_0, _t541_1, _t541_2) = _item540;
            _t541_0.fingerprint(into);
            into.add(_t541_1 as ulong);
            _t541_2.fingerprint(into);
        }
        into.add(this.constrained_aliases.count);
        for (var _item545 in this.constrained_aliases) {
            _item545.fingerprint(into);
        }
        into.add(this.trait_types.count);
        for (var _item547 in this.trait_types) {
            _item547.fingerprint(into);
        }
        into.add(this.conversions.count);
        for (var _item549 in this.conversions) {
            _item549.fingerprint(into);
        }
        into.add(this.overload_sets.count);
        for (var (_key551, _item551) in this.overload_sets) {
            into.add_text(_key551);
            into.add(_item551.count);
            for (var _item553 in _item551) {
                into.add_text(_item553);
            }
        }
        into.add(this.overload_unions.count);
        for (var (_key555, _item555) in this.overload_unions) {
            into.add_text(_key555);
            into.add(_item555.count);
            for (var _item557 in _item555) {
                into.add(_item557.count);
                for (var _item558 in _item557) {
                    into.add_text(_item558);
                }
            }
        }
        into.add(this.method_overload_sets.count);
        for (var (_key560, _item560) in this.method_overload_sets) {
            into.add_text(_key560);
            into.add(_item560.count);
            for (var (_key562, _item562) in _item560) {
                into.add_text(_key562);
                into.add(_item562.count);
                for (var _item564 in _item562) {
                    into.add_text(_item564);
                }
            }
        }
        this.extension_scopes.fingerprint(into);
        into.add(this.private_functions.count);
        for (var _item567 in this.private_functions) {
            _item567.fingerprint(into);
        }
        into.add(this.file_private_functions.count);
        for (var _item569 in this.file_private_functions) {
            _item569.fingerprint(into);
        }
        into.add(this.call_targets.count);
        for (var _item571 in this.call_targets) {
            var (_t572_0, _t572_1) = _item571;
            _t572_0.fingerprint(into);
            into.add_text(_t572_1);
        }
        into.add(this.argument_names.count);
        for (var _item575 in this.argument_names) {
            var (_t576_0, _t576_1) = _item575;
            _t576_0.fingerprint(into);
            into.add_text(_t576_1);
        }
        into.add(this.namespaces.count);
        for (var _item579 in this.namespaces) {
            into.add_text(_item579);
        }
        into.add(this.cached_files.count);
        for (var _item581 in this.cached_files) {
            into.add(_item581 ? 1 : 0);
        }
        into.add(this.recorded_summaries.count);
        for (var (_key583, _item583) in this.recorded_summaries) {
            _key583.fingerprint(into);
            into.add_text(_item583);
        }
        into.add(this.stripped.count);
        for (var _item586 in this.stripped) {
            _item586.fingerprint(into);
        }
        this.templates.fingerprint(into);
        this.checked.fingerprint(into);
        into.add(this.spec_requests.count);
        for (var (_key590, _item590) in this.spec_requests) {
            into.add_text(_key590);
            _item590.fingerprint(into);
        }
        into.add(this.record_summaries ? 1 : 0);
        into.add(this.summaries_to_record.count);
        for (var _item594 in this.summaries_to_record) {
            var (_t595_0, _t595_1) = _item594;
            _t595_0.fingerprint(into);
            into.add_text(_t595_1);
        }
        into.add(this.caller_copies.count);
        for (var (_key598, _item598) in this.caller_copies) {
            into.add_text(_key598);
            into.add(_item598.count);
            for (var _item600 in _item598) {
                into.add(_item600 ? 1 : 0);
            }
        }
        into.add(this.linked ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v508 = JsonValue.array();
        for (var _item508 in this.imports) {
            _v508.append(_item508.to_json());
        }
        out["imports"] = _v508;
        var _v510 = JsonValue.array();
        for (var _item510 in this.structs) {
            _v510.append(_item510.to_json());
        }
        out["structs"] = _v510;
        var _v512 = JsonValue.array();
        for (var _item512 in this.traits) {
            _v512.append(_item512.to_json());
        }
        out["traits"] = _v512;
        var _v514 = JsonValue.array();
        for (var _item514 in this.extensions) {
            _v514.append(_item514.to_json());
        }
        out["extensions"] = _v514;
        var _v516 = JsonValue.array();
        for (var _item516 in this.functions) {
            _v516.append(_item516.to_json());
        }
        out["functions"] = _v516;
        var _v518 = JsonValue.array();
        for (var _item518 in this.externs) {
            _v518.append(_item518.to_json());
        }
        out["externs"] = _v518;
        var _v520 = JsonValue.array();
        for (var _item520 in this.globals) {
            _v520.append(_item520.to_json());
        }
        out["globals"] = _v520;
        var _v522 = JsonValue.array();
        for (var _item522 in this.static_blocks) {
            _v522.append(_item522.to_json());
        }
        out["static_blocks"] = _v522;
        var _v524 = JsonValue.array();
        for (var _item524 in this.enums) {
            _v524.append(_item524.to_json());
        }
        out["enums"] = _v524;
        var _v526 = JsonValue.array();
        for (var _item526 in this.struct_specs) {
            _v526.append(_item526.to_json());
        }
        out["struct_specs"] = _v526;
        var _v528 = JsonValue.array();
        for (var _item528 in this.func_specs) {
            _v528.append(_item528.to_json());
        }
        out["func_specs"] = _v528;
        var _v530 = JsonValue.array();
        for (var _item530 in this.type_aliases) {
            _v530.append(_item530.to_json());
        }
        out["type_aliases"] = _v530;
        var _v532 = JsonValue.array();
        for (var _item532 in this.withheld) {
            _v532.append(_item532.to_json());
        }
        out["withheld"] = _v532;
        var _v534 = JsonValue.array();
        for (var _item534 in this.properties) {
            _v534.append(_item534.to_json());
        }
        out["properties"] = _v534;
        var _v536 = JsonValue.array();
        for (var _item536 in this.type_uses) {
            _v536.append(_item536.to_json());
        }
        out["type_uses"] = _v536;
        var _v538 = JsonValue.array();
        for (var _item538 in this.use_contexts) {
            _v538.append(_item538.to_json());
        }
        out["use_contexts"] = _v538;
        var _v540 = JsonValue.array();
        for (var _item540 in this.literal_args) {
            var _v541 = JsonValue.array();
            var _t541 = _item540;
            var (_t541_0, _t541_1, _t541_2) = _t541;
            _v541.append(_t541_0.to_json());
            _v541.append(unsigned_json(_t541_1));
            _v541.append(_t541_2.to_json());
            _v540.append(_v541);
        }
        out["literal_args"] = _v540;
        var _v545 = JsonValue.array();
        for (var _item545 in this.constrained_aliases) {
            _v545.append(_item545.to_json());
        }
        out["constrained_aliases"] = _v545;
        var _v547 = JsonValue.array();
        for (var _item547 in this.trait_types) {
            _v547.append(_item547.to_json());
        }
        out["trait_types"] = _v547;
        var _v549 = JsonValue.array();
        for (var _item549 in this.conversions) {
            _v549.append(_item549.to_json());
        }
        out["conversions"] = _v549;
        var _v551 = JsonValue.object();
        for (var (_key551, _item551) in this.overload_sets) {
            var _v552 = JsonValue.array();
            for (var _item552 in _item551) {
                _v552.append(JsonValue.String(_item552));
            }
            _v551[_key551] = _v552;
        }
        out["overload_sets"] = _v551;
        var _v554 = JsonValue.object();
        for (var (_key554, _item554) in this.overload_unions) {
            var _v555 = JsonValue.array();
            for (var _item555 in _item554) {
                var _v556 = JsonValue.array();
                for (var _item556 in _item555) {
                    _v556.append(JsonValue.String(_item556));
                }
                _v555.append(_v556);
            }
            _v554[_key554] = _v555;
        }
        out["overload_unions"] = _v554;
        var _v558 = JsonValue.object();
        for (var (_key558, _item558) in this.method_overload_sets) {
            var _v559 = JsonValue.object();
            for (var (_key559, _item559) in _item558) {
                var _v560 = JsonValue.array();
                for (var _item560 in _item559) {
                    _v560.append(JsonValue.String(_item560));
                }
                _v559[_key559] = _v560;
            }
            _v558[_key558] = _v559;
        }
        out["method_overload_sets"] = _v558;
        out["extension_scopes"] = this.extension_scopes.to_json();
        var _v563 = JsonValue.array();
        for (var _item563 in this.private_functions) {
            _v563.append(_item563.to_json());
        }
        out["private_functions"] = _v563;
        var _v565 = JsonValue.array();
        for (var _item565 in this.file_private_functions) {
            _v565.append(_item565.to_json());
        }
        out["file_private_functions"] = _v565;
        var _v567 = JsonValue.array();
        for (var _item567 in this.call_targets) {
            var _v568 = JsonValue.array();
            var _t568 = _item567;
            var (_t568_0, _t568_1) = _t568;
            _v568.append(_t568_0.to_json());
            _v568.append(JsonValue.String(_t568_1));
            _v567.append(_v568);
        }
        out["call_targets"] = _v567;
        var _v571 = JsonValue.array();
        for (var _item571 in this.argument_names) {
            var _v572 = JsonValue.array();
            var _t572 = _item571;
            var (_t572_0, _t572_1) = _t572;
            _v572.append(_t572_0.to_json());
            _v572.append(JsonValue.String(_t572_1));
            _v571.append(_v572);
        }
        out["argument_names"] = _v571;
        var _v575 = JsonValue.array();
        for (var _item575 in this.namespaces) {
            _v575.append(JsonValue.String(_item575));
        }
        out["namespaces"] = _v575;
        var _v577 = JsonValue.array();
        for (var _item577 in this.cached_files) {
            _v577.append(JsonValue.Bool(_item577));
        }
        out["cached_files"] = _v577;
        var _v579 = JsonValue.object();
        for (var (_key579, _item579) in this.recorded_summaries) {
            _v579[_key579.to_json().to_string()] = JsonValue.String(_item579);
        }
        out["recorded_summaries"] = _v579;
        var _v581 = JsonValue.array();
        for (var _item581 in this.stripped) {
            _v581.append(_item581.to_json());
        }
        out["stripped"] = _v581;
        out["templates"] = this.templates.to_json();
        out["checked"] = this.checked.to_json();
        var _v585 = JsonValue.object();
        for (var (_key585, _item585) in this.spec_requests) {
            _v585[_key585] = _item585.to_json();
        }
        out["spec_requests"] = _v585;
        out["record_summaries"] = JsonValue.Bool(this.record_summaries);
        var _v588 = JsonValue.array();
        for (var _item588 in this.summaries_to_record) {
            var _v589 = JsonValue.array();
            var _t589 = _item588;
            var (_t589_0, _t589_1) = _t589;
            _v589.append(_t589_0.to_json());
            _v589.append(JsonValue.String(_t589_1));
            _v588.append(_v589);
        }
        out["summaries_to_record"] = _v588;
        var _v592 = JsonValue.object();
        for (var (_key592, _item592) in this.caller_copies) {
            var _v593 = JsonValue.array();
            for (var _item593 in _item592) {
                _v593.append(JsonValue.Bool(_item593));
            }
            _v592[_key592] = _v593;
        }
        out["caller_copies"] = _v592;
        out["linked"] = JsonValue.Bool(this.linked);
        return out;
    }
}

## `Checked` in `model.rs`.
export struct Checked {
    var structs: HashSet<String>;
    var functions: HashSet<String>;
    var globals: HashSet<String>;
    var extensions: ulong;
    var summaries: HashMap<String, (Loc, String)>;

    construct(
        structs: HashSet<String> = HashSet<String>(),
        functions: HashSet<String> = HashSet<String>(),
        globals: HashSet<String> = HashSet<String>(),
        extensions: ulong = 0,
        summaries: HashMap<String, (Loc, String)> = HashMap<String, (Loc, String)>()
    ) {
        this.structs = structs;
        this.functions = functions;
        this.globals = globals;
        this.extensions = extensions;
        this.summaries = summaries;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Checked {
        var _c603 = HashMap<String, (Loc, String)>();
        for (var (_key603, _item603) in this.summaries) {
            var (_t604_0, _t604_1) = _item603;
            _c603[_key603] = (_t604_0, _t604_1);
        }
        return Checked(
            structs = this.structs.copy(),
            functions = this.functions.copy(),
            globals = this.globals.copy(),
            extensions = this.extensions,
            summaries = _c603
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Checked");
        into.add(this.structs.count);
        for (var _item603 in this.structs) {
            into.add_text(_item603);
        }
        into.add(this.functions.count);
        for (var _item605 in this.functions) {
            into.add_text(_item605);
        }
        into.add(this.globals.count);
        for (var _item607 in this.globals) {
            into.add_text(_item607);
        }
        into.add(this.extensions as ulong);
        into.add(this.summaries.count);
        for (var (_key610, _item610) in this.summaries) {
            into.add_text(_key610);
            var (_t612_0, _t612_1) = _item610;
            _t612_0.fingerprint(into);
            into.add_text(_t612_1);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v596 = JsonValue.array();
        for (var _item596 in this.structs) {
            _v596.append(JsonValue.String(_item596));
        }
        out["structs"] = _v596;
        var _v598 = JsonValue.array();
        for (var _item598 in this.functions) {
            _v598.append(JsonValue.String(_item598));
        }
        out["functions"] = _v598;
        var _v600 = JsonValue.array();
        for (var _item600 in this.globals) {
            _v600.append(JsonValue.String(_item600));
        }
        out["globals"] = _v600;
        out["extensions"] = unsigned_json(this.extensions);
        var _v603 = JsonValue.object();
        for (var (_key603, _item603) in this.summaries) {
            var _v604 = JsonValue.array();
            var _t604 = _item603;
            var (_t604_0, _t604_1) = _t604;
            _v604.append(_t604_0.to_json());
            _v604.append(JsonValue.String(_t604_1));
            _v603[_key603] = _v604;
        }
        out["summaries"] = _v603;
        return out;
    }
}

## `SpecRequest` in `model.rs`.
export struct SpecRequest {
    var by: String;
    var loc: Loc;

    construct(by: String = "", loc: Loc = Loc()) {
        this.by = by;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): SpecRequest {
        return SpecRequest(by = this.by, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("SpecRequest");
        into.add_text(this.by);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["by"] = JsonValue.String(this.by);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `Templates` in `model.rs`.
export struct Templates {
    var frozen: bool;
    var structs: Array<StructDef>;
    var functions: Array<FunctionDef>;

    construct(
        frozen: bool = false,
        structs: Array<StructDef> = Array<StructDef>(),
        functions: Array<FunctionDef> = Array<FunctionDef>()
    ) {
        this.frozen = frozen;
        this.structs = structs;
        this.functions = functions;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): Templates {
        var _c610 = Array<StructDef>();
        for (var _item610 in this.structs) {
            _c610.append(_item610.copy());
        }
        var _c612 = Array<FunctionDef>();
        for (var _item612 in this.functions) {
            _c612.append(_item612.copy());
        }
        return Templates(frozen = this.frozen, structs = _c610, functions = _c612);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Templates");
        into.add(this.frozen ? 1 : 0);
        into.add(this.structs.count);
        for (var _item618 in this.structs) {
            _item618.fingerprint(into);
        }
        into.add(this.functions.count);
        for (var _item620 in this.functions) {
            _item620.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["frozen"] = JsonValue.Bool(this.frozen);
        var _v610 = JsonValue.array();
        for (var _item610 in this.structs) {
            _v610.append(_item610.to_json());
        }
        out["structs"] = _v610;
        var _v612 = JsonValue.array();
        for (var _item612 in this.functions) {
            _v612.append(_item612.to_json());
        }
        out["functions"] = _v612;
        return out;
    }
}

## `TypeFlags` in `model.rs`.
export enum TypeFlags {
    Scalar,
    Function,

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        match (this) {
            Scalar => {
                into.add(0);
            }
            Function => {
                into.add(1);
            }
        }
    }

    to_json(): JsonValue {
        match (this) {
            Scalar => {
                return JsonValue.String("Scalar");
            }
            Function => {
                return JsonValue.String("Function");
            }
        }
    }
}

## `TypeName` in `model.rs`.
export struct TypeName {
    var name: String;
    var sub_types: Array<TypeName>;
    var flags: TypeFlags;
    var labels: Array<String>;

    construct(
        name: String = "",
        sub_types: Array<TypeName> = Array<TypeName>(),
        flags: TypeFlags = TypeFlags.Scalar,
        labels: Array<String> = Array<String>()
    ) {
        this.name = name;
        this.sub_types = sub_types;
        this.flags = flags;
        this.labels = labels;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TypeName {
        var _c615 = Array<TypeName>();
        for (var _item615 in this.sub_types) {
            _c615.append(_item615.copy());
        }
        return TypeName(name = this.name, sub_types = _c615, flags = this.flags, labels = this.labels.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TypeName");
        into.add_text(this.name);
        into.add(this.sub_types.count);
        for (var _item623 in this.sub_types) {
            _item623.fingerprint(into);
        }
        this.flags.fingerprint(into);
        into.add(this.labels.count);
        for (var _item626 in this.labels) {
            into.add_text(_item626);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v615 = JsonValue.array();
        for (var _item615 in this.sub_types) {
            _v615.append(_item615.to_json());
        }
        out["sub_types"] = _v615;
        out["flags"] = this.flags.to_json();
        var _v618 = JsonValue.array();
        for (var _item618 in this.labels) {
            _v618.append(JsonValue.String(_item618));
        }
        out["labels"] = _v618;
        return out;
    }
}

## What `unsigned_json` writes before the digits of a value too large for
## `JsonValue.Integer`; `canonical_json` writes those digits bare.
export const UNSIGNED_MARK = "\u{1}unsigned:";

## Returns `value` as JSON: an integer, or for one past `long`'s range (a
## `WithSubject` id), its digits behind `UNSIGNED_MARK`.
##
## @param value the value
## @returns the JSON
export unsigned_json(value: ulong): JsonValue {
    if (value <= 9223372036854775807) {
        return JsonValue.Integer(value as long);
    }
    return JsonValue.String($"{UNSIGNED_MARK}{value}");
}

_tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}
