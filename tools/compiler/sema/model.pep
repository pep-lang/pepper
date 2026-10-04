## The sema model: `crates/pepper-sema/src/model.rs` and `type_name.rs` in
## Pepper, the tree the builder makes of the linked program and the passes
## rewrite. Each Rust enum variant with named fields holds a struct of its
## own (`SymbolRefExpression` for `Expression::SymbolRef`), so a pass can
## change a node's fields in place. Each type's `to_json()` writes what
## serde writes for the Rust type.

import compiler.ast;
import json;
import [JsonValue] from json;
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["count"] = JsonValue.Integer(this.count as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = JsonValue.Integer(this.id as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = JsonValue.Integer(this.id as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["id"] = JsonValue.Integer(this.id as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["case"] = JsonValue.String(this.case);
        out["case_loc"] = this.case_loc.to_json();
        out["ty"] = (this.ty.is_value() ? this.ty.value().to_json() : JsonValue.Null);
        out["index"] = JsonValue.Integer(this.index as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["owner"] = JsonValue.String(this.owner);
        out["member"] = JsonValue.String(this.member);
        out["name"] = JsonValue.String(this.name);
        out["params"] = JsonValue.Integer(this.params as long);
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

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        var _v384 = JsonValue.array();
        for (var _item384 in this.args) {
            _v384.append(_item384.to_json());
        }
        out["args"] = _v384;
        out["context"] = JsonValue.Integer(this.context as long);
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

    construct(
        target: TypeName = TypeName(),
        resolved: String? = Optional<String>.Empty,
        traits: Array<TypeName> = Array<TypeName>(),
        restated: Array<(ulong, Bound)> = Array<(ulong, Bound)>(),
        methods: Array<FunctionDef> = Array<FunctionDef>(),
        attributes: Array<ast.Attribute> = Array<ast.Attribute>(),
        loc: Loc = Loc(),
        is_exported: bool = false
    ) {
        this.target = target;
        this.resolved = resolved;
        this.traits = traits;
        this.restated = restated;
        this.methods = methods;
        this.attributes = attributes;
        this.loc = loc;
        this.is_exported = is_exported;
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
            is_exported = this.is_exported
        );
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
            _v468.append(JsonValue.Integer(_t468_0 as long));
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
        var _c479 = Array<HashSet<uint>>();
        for (var _item479 in this.visible) {
            _c479.append(_item479.copy());
        }
        return ExtensionScopes(prelude = this.prelude.copy(), visible = _c479, module = this.module.copy());
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v477 = JsonValue.array();
        for (var _item477 in this.prelude) {
            _v477.append(JsonValue.Integer(_item477 as long));
        }
        out["prelude"] = _v477;
        var _v479 = JsonValue.array();
        for (var _item479 in this.visible) {
            var _v480 = JsonValue.array();
            for (var _item480 in _item479) {
                _v480.append(JsonValue.Integer(_item480 as long));
            }
            _v479.append(_v480);
        }
        out["visible"] = _v479;
        var _v482 = JsonValue.array();
        for (var _item482 in this.module) {
            _v482.append((_item482.is_value() ? JsonValue.Integer(_item482.value() as long) : JsonValue.Null));
        }
        out["module"] = _v482;
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
        var _c487 = Array<VariableDef>();
        for (var _item487 in this.parameters) {
            _c487.append(_item487.copy());
        }
        return ExternDef(
            name = this.name,
            ty = this.ty.copy(),
            parameters = _c487,
            is_variadic = this.is_variadic,
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        var _v487 = JsonValue.array();
        for (var _item487 in this.parameters) {
            _v487.append(_item487.to_json());
        }
        out["parameters"] = _v487;
        out["is_variadic"] = JsonValue.Bool(this.is_variadic);
        var _v490 = JsonValue.array();
        for (var _item490 in this.attributes) {
            _v490.append(_item490.to_json());
        }
        out["attributes"] = _v490;
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
        var _c494 = Array<GenericParam>();
        for (var _item494 in this.generic_params) {
            _c494.append(_item494.copy());
        }
        return TypeAliasDef(
            name = this.name,
            generic_params = _c494,
            target = this.target.copy(),
            attributes = this.attributes.copy(),
            loc = this.loc
        );
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v494 = JsonValue.array();
        for (var _item494 in this.generic_params) {
            _v494.append(_item494.to_json());
        }
        out["generic_params"] = _v494;
        out["target"] = this.target.to_json();
        var _v497 = JsonValue.array();
        for (var _item497 in this.attributes) {
            _v497.append(_item497.to_json());
        }
        out["attributes"] = _v497;
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
        var _c509 = Array<StructDef>();
        for (var _item509 in this.structs) {
            _c509.append(_item509.copy());
        }
        var _c511 = Array<TraitDef>();
        for (var _item511 in this.traits) {
            _c511.append(_item511.copy());
        }
        var _c513 = Array<ExtensionDef>();
        for (var _item513 in this.extensions) {
            _c513.append(_item513.copy());
        }
        var _c515 = Array<FunctionDef>();
        for (var _item515 in this.functions) {
            _c515.append(_item515.copy());
        }
        var _c517 = Array<ExternDef>();
        for (var _item517 in this.externs) {
            _c517.append(_item517.copy());
        }
        var _c519 = Array<VariableDef>();
        for (var _item519 in this.globals) {
            _c519.append(_item519.copy());
        }
        var _c521 = Array<ModuleStaticBlock>();
        for (var _item521 in this.static_blocks) {
            _c521.append(_item521.copy());
        }
        var _c523 = Array<EnumDef>();
        for (var _item523 in this.enums) {
            _c523.append(_item523.copy());
        }
        var _c525 = Array<TypeName>();
        for (var _item525 in this.struct_specs) {
            _c525.append(_item525.copy());
        }
        var _c527 = Array<TypeName>();
        for (var _item527 in this.func_specs) {
            _c527.append(_item527.copy());
        }
        var _c529 = Array<TypeAliasDef>();
        for (var _item529 in this.type_aliases) {
            _c529.append(_item529.copy());
        }
        var _c531 = Array<Withheld>();
        for (var _item531 in this.withheld) {
            _c531.append(_item531.copy());
        }
        var _c533 = Array<PropertyDef>();
        for (var _item533 in this.properties) {
            _c533.append(_item533.copy());
        }
        var _c535 = Array<TypeUse>();
        for (var _item535 in this.type_uses) {
            _c535.append(_item535.copy());
        }
        var _c537 = Array<UseContext>();
        for (var _item537 in this.use_contexts) {
            _c537.append(_item537.copy());
        }
        var _c539 = Array<(Loc, ulong, Loc)>();
        for (var _item539 in this.literal_args) {
            var (_t540_0, _t540_1, _t540_2) = _item539;
            _c539.append((_t540_0, _t540_1, _t540_2));
        }
        var _c544 = Array<TypeAliasDef>();
        for (var _item544 in this.constrained_aliases) {
            _c544.append(_item544.copy());
        }
        var _c546 = Array<TraitType>();
        for (var _item546 in this.trait_types) {
            _c546.append(_item546.copy());
        }
        var _c548 = Array<Conversion>();
        for (var _item548 in this.conversions) {
            _c548.append(_item548.copy());
        }
        var _c550 = Map<String, Array<String>>();
        for (var (_key550, _item550) in this.overload_sets) {
            _c550[_key550] = _item550.copy();
        }
        var _c553 = Map<String, Array<Array<String>>>();
        for (var (_key553, _item553) in this.overload_unions) {
            var _c554 = Array<Array<String>>();
            for (var _item554 in _item553) {
                _c554.append(_item554.copy());
            }
            _c553[_key553] = _c554;
        }
        var _c557 = Map<String, Map<String, Array<String>>>();
        for (var (_key557, _item557) in this.method_overload_sets) {
            var _c558 = Map<String, Array<String>>();
            for (var (_key558, _item558) in _item557) {
                _c558[_key558] = _item558.copy();
            }
            _c557[_key557] = _c558;
        }
        var _c564 = Array<(Loc, String)>();
        for (var _item564 in this.call_targets) {
            var (_t565_0, _t565_1) = _item564;
            _c564.append((_t565_0, _t565_1));
        }
        var _c568 = Array<(Loc, String)>();
        for (var _item568 in this.argument_names) {
            var (_t569_0, _t569_1) = _item568;
            _c568.append((_t569_0, _t569_1));
        }
        var _c576 = HashMap<Loc, String>();
        for (var (_key576, _item576) in this.recorded_summaries) {
            _c576[_key576] = _item576;
        }
        var _c582 = HashMap<String, SpecRequest>();
        for (var (_key582, _item582) in this.spec_requests) {
            _c582[_key582] = _item582.copy();
        }
        var _c585 = Array<(Loc, String)>();
        for (var _item585 in this.summaries_to_record) {
            var (_t586_0, _t586_1) = _item585;
            _c585.append((_t586_0, _t586_1));
        }
        var _c589 = HashMap<String, Array<bool>>();
        for (var (_key589, _item589) in this.caller_copies) {
            _c589[_key589] = _item589.copy();
        }
        return Module(
            imports = this.imports.copy(),
            structs = _c509,
            traits = _c511,
            extensions = _c513,
            functions = _c515,
            externs = _c517,
            globals = _c519,
            static_blocks = _c521,
            enums = _c523,
            struct_specs = _c525,
            func_specs = _c527,
            type_aliases = _c529,
            withheld = _c531,
            properties = _c533,
            type_uses = _c535,
            use_contexts = _c537,
            literal_args = _c539,
            constrained_aliases = _c544,
            trait_types = _c546,
            conversions = _c548,
            overload_sets = _c550,
            overload_unions = _c553,
            method_overload_sets = _c557,
            extension_scopes = this.extension_scopes.copy(),
            private_functions = this.private_functions.copy(),
            call_targets = _c564,
            argument_names = _c568,
            namespaces = this.namespaces.copy(),
            cached_files = this.cached_files.copy(),
            recorded_summaries = _c576,
            stripped = this.stripped.copy(),
            templates = this.templates.copy(),
            checked = this.checked.copy(),
            spec_requests = _c582,
            record_summaries = this.record_summaries,
            summaries_to_record = _c585,
            caller_copies = _c589,
            linked = this.linked
        );
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v507 = JsonValue.array();
        for (var _item507 in this.imports) {
            _v507.append(_item507.to_json());
        }
        out["imports"] = _v507;
        var _v509 = JsonValue.array();
        for (var _item509 in this.structs) {
            _v509.append(_item509.to_json());
        }
        out["structs"] = _v509;
        var _v511 = JsonValue.array();
        for (var _item511 in this.traits) {
            _v511.append(_item511.to_json());
        }
        out["traits"] = _v511;
        var _v513 = JsonValue.array();
        for (var _item513 in this.extensions) {
            _v513.append(_item513.to_json());
        }
        out["extensions"] = _v513;
        var _v515 = JsonValue.array();
        for (var _item515 in this.functions) {
            _v515.append(_item515.to_json());
        }
        out["functions"] = _v515;
        var _v517 = JsonValue.array();
        for (var _item517 in this.externs) {
            _v517.append(_item517.to_json());
        }
        out["externs"] = _v517;
        var _v519 = JsonValue.array();
        for (var _item519 in this.globals) {
            _v519.append(_item519.to_json());
        }
        out["globals"] = _v519;
        var _v521 = JsonValue.array();
        for (var _item521 in this.static_blocks) {
            _v521.append(_item521.to_json());
        }
        out["static_blocks"] = _v521;
        var _v523 = JsonValue.array();
        for (var _item523 in this.enums) {
            _v523.append(_item523.to_json());
        }
        out["enums"] = _v523;
        var _v525 = JsonValue.array();
        for (var _item525 in this.struct_specs) {
            _v525.append(_item525.to_json());
        }
        out["struct_specs"] = _v525;
        var _v527 = JsonValue.array();
        for (var _item527 in this.func_specs) {
            _v527.append(_item527.to_json());
        }
        out["func_specs"] = _v527;
        var _v529 = JsonValue.array();
        for (var _item529 in this.type_aliases) {
            _v529.append(_item529.to_json());
        }
        out["type_aliases"] = _v529;
        var _v531 = JsonValue.array();
        for (var _item531 in this.withheld) {
            _v531.append(_item531.to_json());
        }
        out["withheld"] = _v531;
        var _v533 = JsonValue.array();
        for (var _item533 in this.properties) {
            _v533.append(_item533.to_json());
        }
        out["properties"] = _v533;
        var _v535 = JsonValue.array();
        for (var _item535 in this.type_uses) {
            _v535.append(_item535.to_json());
        }
        out["type_uses"] = _v535;
        var _v537 = JsonValue.array();
        for (var _item537 in this.use_contexts) {
            _v537.append(_item537.to_json());
        }
        out["use_contexts"] = _v537;
        var _v539 = JsonValue.array();
        for (var _item539 in this.literal_args) {
            var _v540 = JsonValue.array();
            var _t540 = _item539;
            var (_t540_0, _t540_1, _t540_2) = _t540;
            _v540.append(_t540_0.to_json());
            _v540.append(JsonValue.Integer(_t540_1 as long));
            _v540.append(_t540_2.to_json());
            _v539.append(_v540);
        }
        out["literal_args"] = _v539;
        var _v544 = JsonValue.array();
        for (var _item544 in this.constrained_aliases) {
            _v544.append(_item544.to_json());
        }
        out["constrained_aliases"] = _v544;
        var _v546 = JsonValue.array();
        for (var _item546 in this.trait_types) {
            _v546.append(_item546.to_json());
        }
        out["trait_types"] = _v546;
        var _v548 = JsonValue.array();
        for (var _item548 in this.conversions) {
            _v548.append(_item548.to_json());
        }
        out["conversions"] = _v548;
        var _v550 = JsonValue.object();
        for (var (_key550, _item550) in this.overload_sets) {
            var _v551 = JsonValue.array();
            for (var _item551 in _item550) {
                _v551.append(JsonValue.String(_item551));
            }
            _v550[_key550] = _v551;
        }
        out["overload_sets"] = _v550;
        var _v553 = JsonValue.object();
        for (var (_key553, _item553) in this.overload_unions) {
            var _v554 = JsonValue.array();
            for (var _item554 in _item553) {
                var _v555 = JsonValue.array();
                for (var _item555 in _item554) {
                    _v555.append(JsonValue.String(_item555));
                }
                _v554.append(_v555);
            }
            _v553[_key553] = _v554;
        }
        out["overload_unions"] = _v553;
        var _v557 = JsonValue.object();
        for (var (_key557, _item557) in this.method_overload_sets) {
            var _v558 = JsonValue.object();
            for (var (_key558, _item558) in _item557) {
                var _v559 = JsonValue.array();
                for (var _item559 in _item558) {
                    _v559.append(JsonValue.String(_item559));
                }
                _v558[_key558] = _v559;
            }
            _v557[_key557] = _v558;
        }
        out["method_overload_sets"] = _v557;
        out["extension_scopes"] = this.extension_scopes.to_json();
        var _v562 = JsonValue.array();
        for (var _item562 in this.private_functions) {
            _v562.append(_item562.to_json());
        }
        out["private_functions"] = _v562;
        var _v564 = JsonValue.array();
        for (var _item564 in this.call_targets) {
            var _v565 = JsonValue.array();
            var _t565 = _item564;
            var (_t565_0, _t565_1) = _t565;
            _v565.append(_t565_0.to_json());
            _v565.append(JsonValue.String(_t565_1));
            _v564.append(_v565);
        }
        out["call_targets"] = _v564;
        var _v568 = JsonValue.array();
        for (var _item568 in this.argument_names) {
            var _v569 = JsonValue.array();
            var _t569 = _item568;
            var (_t569_0, _t569_1) = _t569;
            _v569.append(_t569_0.to_json());
            _v569.append(JsonValue.String(_t569_1));
            _v568.append(_v569);
        }
        out["argument_names"] = _v568;
        var _v572 = JsonValue.array();
        for (var _item572 in this.namespaces) {
            _v572.append(JsonValue.String(_item572));
        }
        out["namespaces"] = _v572;
        var _v574 = JsonValue.array();
        for (var _item574 in this.cached_files) {
            _v574.append(JsonValue.Bool(_item574));
        }
        out["cached_files"] = _v574;
        var _v576 = JsonValue.object();
        for (var (_key576, _item576) in this.recorded_summaries) {
            _v576[_key576.to_json().to_string()] = JsonValue.String(_item576);
        }
        out["recorded_summaries"] = _v576;
        var _v578 = JsonValue.array();
        for (var _item578 in this.stripped) {
            _v578.append(_item578.to_json());
        }
        out["stripped"] = _v578;
        out["templates"] = this.templates.to_json();
        out["checked"] = this.checked.to_json();
        var _v582 = JsonValue.object();
        for (var (_key582, _item582) in this.spec_requests) {
            _v582[_key582] = _item582.to_json();
        }
        out["spec_requests"] = _v582;
        out["record_summaries"] = JsonValue.Bool(this.record_summaries);
        var _v585 = JsonValue.array();
        for (var _item585 in this.summaries_to_record) {
            var _v586 = JsonValue.array();
            var _t586 = _item585;
            var (_t586_0, _t586_1) = _t586;
            _v586.append(_t586_0.to_json());
            _v586.append(JsonValue.String(_t586_1));
            _v585.append(_v586);
        }
        out["summaries_to_record"] = _v585;
        var _v589 = JsonValue.object();
        for (var (_key589, _item589) in this.caller_copies) {
            var _v590 = JsonValue.array();
            for (var _item590 in _item589) {
                _v590.append(JsonValue.Bool(_item590));
            }
            _v589[_key589] = _v590;
        }
        out["caller_copies"] = _v589;
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
        var _c600 = HashMap<String, (Loc, String)>();
        for (var (_key600, _item600) in this.summaries) {
            var (_t601_0, _t601_1) = _item600;
            _c600[_key600] = (_t601_0, _t601_1);
        }
        return Checked(
            structs = this.structs.copy(),
            functions = this.functions.copy(),
            globals = this.globals.copy(),
            extensions = this.extensions,
            summaries = _c600
        );
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v593 = JsonValue.array();
        for (var _item593 in this.structs) {
            _v593.append(JsonValue.String(_item593));
        }
        out["structs"] = _v593;
        var _v595 = JsonValue.array();
        for (var _item595 in this.functions) {
            _v595.append(JsonValue.String(_item595));
        }
        out["functions"] = _v595;
        var _v597 = JsonValue.array();
        for (var _item597 in this.globals) {
            _v597.append(JsonValue.String(_item597));
        }
        out["globals"] = _v597;
        out["extensions"] = JsonValue.Integer(this.extensions as long);
        var _v600 = JsonValue.object();
        for (var (_key600, _item600) in this.summaries) {
            var _v601 = JsonValue.array();
            var _t601 = _item600;
            var (_t601_0, _t601_1) = _t601;
            _v601.append(_t601_0.to_json());
            _v601.append(JsonValue.String(_t601_1));
            _v600[_key600] = _v601;
        }
        out["summaries"] = _v600;
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
        var _c607 = Array<StructDef>();
        for (var _item607 in this.structs) {
            _c607.append(_item607.copy());
        }
        var _c609 = Array<FunctionDef>();
        for (var _item609 in this.functions) {
            _c609.append(_item609.copy());
        }
        return Templates(frozen = this.frozen, structs = _c607, functions = _c609);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["frozen"] = JsonValue.Bool(this.frozen);
        var _v607 = JsonValue.array();
        for (var _item607 in this.structs) {
            _v607.append(_item607.to_json());
        }
        out["structs"] = _v607;
        var _v609 = JsonValue.array();
        for (var _item609 in this.functions) {
            _v609.append(_item609.to_json());
        }
        out["functions"] = _v609;
        return out;
    }
}

## `TypeFlags` in `model.rs`.
export enum TypeFlags {
    Scalar,
    Function,

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
        var _c612 = Array<TypeName>();
        for (var _item612 in this.sub_types) {
            _c612.append(_item612.copy());
        }
        return TypeName(name = this.name, sub_types = _c612, flags = this.flags, labels = this.labels.copy());
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v612 = JsonValue.array();
        for (var _item612 in this.sub_types) {
            _v612.append(_item612.to_json());
        }
        out["sub_types"] = _v612;
        out["flags"] = this.flags.to_json();
        var _v615 = JsonValue.array();
        for (var _item615 in this.labels) {
            _v615.append(JsonValue.String(_item615));
        }
        out["labels"] = _v615;
        return out;
    }
}

_tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}
