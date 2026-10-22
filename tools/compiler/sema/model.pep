## The sema model: the tree the builder makes of the linked program and
## the passes rewrite. Each enum variant with named fields holds a struct of
## its own (`SymbolRefExpression` for `Expression.SymbolRef`), so a pass can
## change a node's fields in place. Each type's `to_json()` writes it as
## `pep-build --emit-model` prints it.
##
## The fields declared here are the model; the rest of each type is
## generated from them: change a type's fields, then run
## `scripts/gen-sema-model.py` and `scripts/gen-sema-record.py`.

import compiler.ast;
import json;
import [JsonValue] from json;
import [Fingerprint] from "fingerprint";
import [Loc] from "loc";
import [UnitDecls, PendingBody] from "pending";

## `BinaryOp`, a type of the sema model.
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

## `UnaryOp`, a type of the sema model.
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

## `Kind`, a type of the sema model.
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

## `AtomicFetchOp`, a type of the sema model.
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

## `SimdOp`, a type of the sema model.
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

## `CastKind`, a type of the sema model.
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

## `Expression`, a type of the sema model.
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

## The fields of `Expression.SymbolRef`.
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

## The fields of `Expression.MemberRef`.
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

## The fields of `Expression.StringLiteral`.
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

## The fields of `Expression.Binary`.
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

## The fields of `Expression.Unary`.
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

## The fields of `Expression.Cast`.
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

## The fields of `Expression.Ternary`.
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

## The fields of `Expression.Index`.
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

## The fields of `Expression.ArrayIndex`.
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

## The fields of `Expression.Simd`.
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
        var _c33 = Array<Expression>();
        for (var _item33 in this.args) {
            _c33.append(_item33.copy());
        }
        return SimdExpression(op = this.op, ty = this.ty.copy(), args = _c33, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("SimdExpression");
        this.op.fingerprint(into);
        this.ty.fingerprint(into);
        into.add(this.args.count);
        for (var _item33 in this.args) {
            _item33.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["op"] = this.op.to_json();
        out["ty"] = this.ty.to_json();
        var _v33 = JsonValue.array();
        for (var _item33 in this.args) {
            _v33.append(_item33.to_json());
        }
        out["args"] = _v33;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `Expression.CountStep`.
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

## The fields of `Expression.FunctionPointer`.
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
        var _c39 = Optional<TypeName>.Empty;
        if (this.owner.is_value()) {
            _c39 = Optional<TypeName>.Value(this.owner.value().copy());
        }
        return FunctionPointerExpression(owner = _c39, function = this.function, loc = this.loc);
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

## The fields of `Expression.FunctionCall`.
export struct FunctionCallExpression {
    var function: String;
    var args: Array<Expression>;
    var loc: Loc;
    var labeled: TypeName?;

    construct(
        function: String = "",
        args: Array<Expression> = Array<Expression>(),
        loc: Loc = Loc(),
        labeled: TypeName? = Optional<TypeName>.Empty
    ) {
        this.function = function;
        this.args = args;
        this.loc = loc;
        this.labeled = labeled;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): FunctionCallExpression {
        var _c44 = Array<Expression>();
        for (var _item44 in this.args) {
            _c44.append(_item44.copy());
        }
        var _c47 = Optional<TypeName>.Empty;
        if (this.labeled.is_value()) {
            _c47 = Optional<TypeName>.Value(this.labeled.value().copy());
        }
        return FunctionCallExpression(function = this.function, args = _c44, loc = this.loc, labeled = _c47);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionCallExpression");
        into.add_text(this.function);
        into.add(this.args.count);
        for (var _item44 in this.args) {
            _item44.fingerprint(into);
        }
        this.loc.fingerprint(into);
        if (this.labeled.is_value()) {
            this.labeled.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["function"] = JsonValue.String(this.function);
        var _v44 = JsonValue.array();
        for (var _item44 in this.args) {
            _v44.append(_item44.to_json());
        }
        out["args"] = _v44;
        out["loc"] = this.loc.to_json();
        out["labeled"] = (this.labeled.is_value() ? this.labeled.value().to_json() : JsonValue.Null);
        return out;
    }
}

## The fields of `Expression.NamedArgument`.
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

## The fields of `Expression.DefaultArgument`.
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

## The fields of `Expression.MethodCall`.
export struct MethodCallExpression {
    var this_value: Expression;
    var method: String;
    var args: Array<Expression>;
    var loc: Loc;
    var labeled: TypeName?;

    construct(
        this_value: Expression,
        method: String = "",
        args: Array<Expression> = Array<Expression>(),
        loc: Loc = Loc(),
        labeled: TypeName? = Optional<TypeName>.Empty
    ) {
        this.this_value = this_value;
        this.method = method;
        this.args = args;
        this.loc = loc;
        this.labeled = labeled;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): MethodCallExpression {
        var _c55 = Array<Expression>();
        for (var _item55 in this.args) {
            _c55.append(_item55.copy());
        }
        var _c58 = Optional<TypeName>.Empty;
        if (this.labeled.is_value()) {
            _c58 = Optional<TypeName>.Value(this.labeled.value().copy());
        }
        return MethodCallExpression(
            this_value = this.this_value.copy(), method = this.method, args = _c55, loc = this.loc, labeled = _c58
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
        for (var _item55 in this.args) {
            _item55.fingerprint(into);
        }
        this.loc.fingerprint(into);
        if (this.labeled.is_value()) {
            this.labeled.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["this"] = this.this_value.to_json();
        out["method"] = JsonValue.String(this.method);
        var _v55 = JsonValue.array();
        for (var _item55 in this.args) {
            _v55.append(_item55.to_json());
        }
        out["args"] = _v55;
        out["loc"] = this.loc.to_json();
        out["labeled"] = (this.labeled.is_value() ? this.labeled.value().to_json() : JsonValue.Null);
        return out;
    }
}

## The fields of `Expression.FunctionRef`.
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

## The fields of `Expression.Invoke`.
export struct InvokeExpression {
    var callee: Expression;
    var args: Array<Expression>;

    construct(callee: Expression, args: Array<Expression> = Array<Expression>()) {
        this.callee = callee;
        this.args = args;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): InvokeExpression {
        var _c64 = Array<Expression>();
        for (var _item64 in this.args) {
            _c64.append(_item64.copy());
        }
        return InvokeExpression(callee = this.callee.copy(), args = _c64);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("InvokeExpression");
        this.callee.fingerprint(into);
        into.add(this.args.count);
        for (var _item64 in this.args) {
            _item64.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["callee"] = this.callee.to_json();
        var _v64 = JsonValue.array();
        for (var _item64 in this.args) {
            _v64.append(_item64.to_json());
        }
        out["args"] = _v64;
        return out;
    }
}

## The fields of `Expression.MakeClosure`.
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

## The fields of `Expression.CallPointer`.
export struct CallPointerExpression {
    var pointer: Expression;
    var args: Array<Expression>;

    construct(pointer: Expression, args: Array<Expression> = Array<Expression>()) {
        this.pointer = pointer;
        this.args = args;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): CallPointerExpression {
        var _c71 = Array<Expression>();
        for (var _item71 in this.args) {
            _c71.append(_item71.copy());
        }
        return CallPointerExpression(pointer = this.pointer.copy(), args = _c71);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CallPointerExpression");
        this.pointer.fingerprint(into);
        into.add(this.args.count);
        for (var _item71 in this.args) {
            _item71.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["pointer"] = this.pointer.to_json();
        var _v71 = JsonValue.array();
        for (var _item71 in this.args) {
            _v71.append(_item71.to_json());
        }
        out["args"] = _v71;
        return out;
    }
}

## The fields of `Expression.Move`.
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

## The fields of `Expression.Destructure`.
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

## The fields of `Expression.StaticCase`.
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

## The fields of `Expression.StaticString`.
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

## The fields of `Expression.Subject`.
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

## The fields of `Expression.ToTrait`.
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

## The fields of `Expression.FromTrait`.
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
        var _c92 = Array<TypeName>();
        for (var _item92 in this.candidates) {
            _c92.append(_item92.copy());
        }
        return FromTraitExpression(
            value = this.value.copy(),
            from = this.from.copy(),
            to = this.to.copy(),
            candidates = _c92,
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
        for (var _item92 in this.candidates) {
            _item92.fingerprint(into);
        }
        into.add(this.test ? 1 : 0);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = this.value.to_json();
        out["from"] = this.from.to_json();
        out["to"] = this.to.to_json();
        var _v92 = JsonValue.array();
        for (var _item92 in this.candidates) {
            _v92.append(_item92.to_json());
        }
        out["candidates"] = _v92;
        out["test"] = JsonValue.Bool(this.test);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `StaticValue`, a type of the sema model.
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

## `StaticMember`, a type of the sema model.
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
        var _c138 = Array<Expression>();
        for (var _item138 in this.args) {
            _c138.append(_item138.copy());
        }
        return StaticMember(
            member = this.member,
            method = this.method,
            args = _c138,
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
        for (var _item138 in this.args) {
            _item138.fingerprint(into);
        }
        this.loc.fingerprint(into);
        into.add(this.argument_spans.count);
        for (var _item142 in this.argument_spans) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["member"] = this.member.to_json();
        out["method"] = JsonValue.String(this.method);
        var _v138 = JsonValue.array();
        for (var _item138 in this.args) {
            _v138.append(_item138.to_json());
        }
        out["args"] = _v138;
        out["loc"] = this.loc.to_json();
        out["span"] = this.span.to_json();
        var _v142 = JsonValue.array();
        for (var _item142 in this.argument_spans) {
            _v142.append(_item142.to_json());
        }
        out["argument_spans"] = _v142;
        return out;
    }
}

## `MatchArmTest`, a type of the sema model.
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
        var _c145 = Array<CasePattern>();
        for (var _item145 in this.patterns) {
            _c145.append(_item145.copy());
        }
        var _c148 = Array<ElementName>();
        for (var _item148 in this.element_names) {
            _c148.append(_item148.copy());
        }
        return MatchArmTest(
            subject = this.subject.copy(),
            patterns = _c145,
            site = this.site.copy(),
            element_names = _c148,
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
        for (var _item145 in this.patterns) {
            _item145.fingerprint(into);
        }
        this.site.fingerprint(into);
        into.add(this.element_names.count);
        for (var _item148 in this.element_names) {
            _item148.fingerprint(into);
        }
        into.add(this.guarded ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["subject"] = this.subject.to_json();
        var _v145 = JsonValue.array();
        for (var _item145 in this.patterns) {
            _v145.append(_item145.to_json());
        }
        out["patterns"] = _v145;
        out["site"] = this.site.to_json();
        var _v148 = JsonValue.array();
        for (var _item148 in this.element_names) {
            _v148.append(_item148.to_json());
        }
        out["element_names"] = _v148;
        out["guarded"] = JsonValue.Bool(this.guarded);
        return out;
    }
}

## `ElementName`, a type of the sema model.
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
        var _c154 = Optional<(String, Loc)>.Empty;
        if (this.missing.is_value()) {
            var (_t155_0, _t155_1) = this.missing.value();
            _c154 = Optional<(String, Loc)>.Value((_t155_0, _t155_1));
        }
        return ElementName(name = this.name, loc = this.loc, declared = this.declared, missing = _c154);
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
            var (_t155_0, _t155_1) = this.missing.value();
            into.add_text(_t155_0);
            _t155_1.fingerprint(into);
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
        var _v154 = JsonValue.Null;
        if (this.missing.is_value()) {
            var _v155 = JsonValue.array();
            var _t155 = this.missing.value();
            var (_t155_0, _t155_1) = _t155;
            _v155.append(JsonValue.String(_t155_0));
            _v155.append(_t155_1.to_json());
            _v154 = _v155;
        }
        out["missing"] = _v154;
        return out;
    }
}

## `MatchSite`, a type of the sema model.
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

## `WithSubject`, a type of the sema model.
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

## `CaseValue`, a type of the sema model.
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
        var _c172 = Array<CaseChoice>();
        for (var _item172 in this.choices) {
            _c172.append(_item172.copy());
        }
        return CaseValue(subject = this.subject.copy(), name = this.name, choices = _c172, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("CaseValue");
        this.subject.fingerprint(into);
        into.add_text(this.name);
        into.add(this.choices.count);
        for (var _item172 in this.choices) {
            _item172.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["subject"] = this.subject.to_json();
        out["name"] = JsonValue.String(this.name);
        var _v172 = JsonValue.array();
        for (var _item172 in this.choices) {
            _v172.append(_item172.to_json());
        }
        out["choices"] = _v172;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CaseChoice`, a type of the sema model.
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
        var _c177 = Optional<TypeName>.Empty;
        if (this.ty.is_value()) {
            _c177 = Optional<TypeName>.Value(this.ty.value().copy());
        }
        return CaseChoice(
            case = this.case,
            case_loc = this.case_loc,
            ty = _c177,
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
        for (var _item180 in this.bindings) {
            _item180.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["case"] = JsonValue.String(this.case);
        out["case_loc"] = this.case_loc.to_json();
        out["ty"] = (this.ty.is_value() ? this.ty.value().to_json() : JsonValue.Null);
        out["index"] = unsigned_json(this.index);
        var _v180 = JsonValue.array();
        for (var _item180 in this.bindings) {
            _v180.append(_item180.to_json());
        }
        out["bindings"] = _v180;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CasePattern`, a type of the sema model.
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
        var _c183 = Optional<TypeName>.Empty;
        if (this.qualifier.is_value()) {
            _c183 = Optional<TypeName>.Value(this.qualifier.value().copy());
        }
        var _c187 = Optional<Array<CasePattern>>.Empty;
        if (this.bindings.is_value()) {
            var _c188 = Array<CasePattern>();
            for (var _item188 in this.bindings.value()) {
                _c188.append(_item188.copy());
            }
            _c187 = Optional<Array<CasePattern>>.Value(_c188);
        }
        var _c190 = Optional<Expression>.Empty;
        if (this.literal.is_value()) {
            _c190 = Optional<Expression>.Value(this.literal.value().copy());
        }
        var _c192 = Optional<Array<CasePattern>>.Empty;
        if (this.elements.is_value()) {
            var _c193 = Array<CasePattern>();
            for (var _item193 in this.elements.value()) {
                _c193.append(_item193.copy());
            }
            _c192 = Optional<Array<CasePattern>>.Value(_c193);
        }
        var _c197 = Optional<(long, long)>.Empty;
        if (this.values.is_value()) {
            var (_t198_0, _t198_1) = this.values.value();
            _c197 = Optional<(long, long)>.Value((_t198_0, _t198_1));
        }
        var _c201 = Optional<TypeName>.Empty;
        if (this.ty.is_value()) {
            _c201 = Optional<TypeName>.Value(this.ty.value().copy());
        }
        return CasePattern(
            qualifier = _c183,
            case = this.case,
            loc = this.loc,
            bindings = _c187,
            literal = _c190,
            elements = _c192,
            range = this.range,
            constant = this.constant,
            values = _c197,
            ty = _c201
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
            for (var _item188 in this.bindings.value()) {
                _item188.fingerprint(into);
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
            for (var _item193 in this.elements.value()) {
                _item193.fingerprint(into);
            }
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.range ? 1 : 0);
        into.add(this.constant ? 1 : 0);
        if (this.values.is_value()) {
            var (_t198_0, _t198_1) = this.values.value();
            into.add(_t198_0 as ulong);
            into.add(_t198_1 as ulong);
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
        var _v187 = JsonValue.Null;
        if (this.bindings.is_value()) {
            var _v188 = JsonValue.array();
            for (var _item188 in this.bindings.value()) {
                _v188.append(_item188.to_json());
            }
            _v187 = _v188;
        }
        out["bindings"] = _v187;
        out["literal"] = (this.literal.is_value() ? this.literal.value().to_json() : JsonValue.Null);
        var _v192 = JsonValue.Null;
        if (this.elements.is_value()) {
            var _v193 = JsonValue.array();
            for (var _item193 in this.elements.value()) {
                _v193.append(_item193.to_json());
            }
            _v192 = _v193;
        }
        out["elements"] = _v192;
        out["range"] = JsonValue.Bool(this.range);
        out["constant"] = JsonValue.Bool(this.constant);
        var _v197 = JsonValue.Null;
        if (this.values.is_value()) {
            var _v198 = JsonValue.array();
            var _t198 = this.values.value();
            var (_t198_0, _t198_1) = _t198;
            _v198.append(JsonValue.Integer(_t198_0 as long));
            _v198.append(JsonValue.Integer(_t198_1 as long));
            _v197 = _v198;
        }
        out["values"] = _v197;
        out["ty"] = (this.ty.is_value() ? this.ty.value().to_json() : JsonValue.Null);
        return out;
    }
}

## `EnumDef`, a type of the sema model.
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
        var _c205 = Array<EnumCaseDef>();
        for (var _item205 in this.cases) {
            _c205.append(_item205.copy());
        }
        return EnumDef(
            name = this.name,
            representation = this.representation.copy(),
            cases = _c205,
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
        for (var _item205 in this.cases) {
            _item205.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item207 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["representation"] = this.representation.to_json();
        var _v205 = JsonValue.array();
        for (var _item205 in this.cases) {
            _v205.append(_item205.to_json());
        }
        out["cases"] = _v205;
        var _v207 = JsonValue.array();
        for (var _item207 in this.attributes) {
            _v207.append(_item207.to_json());
        }
        out["attributes"] = _v207;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `EnumCaseDef`, a type of the sema model.
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
        var _c212 = Array<(String, Loc)>();
        for (var _item212 in this.payload) {
            var (_t213_0, _t213_1) = _item212;
            _c212.append((_t213_0, _t213_1));
        }
        return EnumCaseDef(
            name = this.name, value = this.value, payload = _c212, attributes = this.attributes.copy(), loc = this.loc
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
        for (var _item212 in this.payload) {
            var (_t213_0, _t213_1) = _item212;
            into.add_text(_t213_0);
            _t213_1.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item216 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["value"] = JsonValue.Integer(this.value as long);
        var _v212 = JsonValue.array();
        for (var _item212 in this.payload) {
            var _v213 = JsonValue.array();
            var _t213 = _item212;
            var (_t213_0, _t213_1) = _t213;
            _v213.append(JsonValue.String(_t213_0));
            _v213.append(_t213_1.to_json());
            _v212.append(_v213);
        }
        out["payload"] = _v212;
        var _v216 = JsonValue.array();
        for (var _item216 in this.attributes) {
            _v216.append(_item216.to_json());
        }
        out["attributes"] = _v216;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `ClosureLiteral`, a type of the sema model.
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
        var _c219 = Array<VariableDef>();
        for (var _item219 in this.parameters) {
            _c219.append(_item219.copy());
        }
        return ClosureLiteral(
            parameters = _c219,
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
        for (var _item219 in this.parameters) {
            _item219.fingerprint(into);
        }
        this.ty.fingerprint(into);
        this.body.fingerprint(into);
        into.add(this.expression_body ? 1 : 0);
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v219 = JsonValue.array();
        for (var _item219 in this.parameters) {
            _v219.append(_item219.to_json());
        }
        out["parameters"] = _v219;
        out["ty"] = this.ty.to_json();
        out["body"] = this.body.to_json();
        out["expression_body"] = JsonValue.Bool(this.expression_body);
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `CountField`, a type of the sema model.
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

## `WeakOp`, a type of the sema model.
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

## `Block`, a type of the sema model.
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
        var _c226 = Array<Statement>();
        for (var _item226 in this.items) {
            _c226.append(_item226.copy());
        }
        return Block(name = this.name, items = _c226, attributes = this.attributes.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Block");
        into.add_text(this.name);
        into.add(this.items.count);
        for (var _item226 in this.items) {
            _item226.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item228 in this.attributes) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v226 = JsonValue.array();
        for (var _item226 in this.items) {
            _v226.append(_item226.to_json());
        }
        out["items"] = _v226;
        var _v228 = JsonValue.array();
        for (var _item228 in this.attributes) {
            _v228.append(_item228.to_json());
        }
        out["attributes"] = _v228;
        return out;
    }
}

## `Branch`, a type of the sema model.
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
        var _c232 = Optional<Block>.Empty;
        if (this.else_block.is_value()) {
            _c232 = Optional<Block>.Value(this.else_block.value().copy());
        }
        return Branch(condition = this.condition.copy(), if_block = this.if_block.copy(), else_block = _c232);
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

## `While`, a type of the sema model.
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

## `ReturnStatement`, a type of the sema model.
export struct ReturnStatement {
    var expr: Expression?;
    var loc: Loc;

    construct(expr: Expression? = Optional<Expression>.Empty, loc: Loc = Loc()) {
        this.expr = expr;
        this.loc = loc;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ReturnStatement {
        var _c236 = Optional<Expression>.Empty;
        if (this.expr.is_value()) {
            _c236 = Optional<Expression>.Value(this.expr.value().copy());
        }
        return ReturnStatement(expr = _c236, loc = this.loc);
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

## `LoopBreakKind`, a type of the sema model.
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

## `LoopBreak`, a type of the sema model.
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

## `Statement`, a type of the sema model.
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

## `StaticPass`, a type of the sema model.
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
        var _c251 = Array<(String, StaticConstant)>();
        for (var _item251 in this.values) {
            var (_t252_0, _t252_1) = _item251;
            _c251.append((_t252_0, _t252_1.copy()));
        }
        var _c257 = Array<(Loc, uint)>();
        for (var _item257 in this.lines) {
            var (_t258_0, _t258_1) = _item257;
            _c257.append((_t258_0, _t258_1));
        }
        return StaticPass(loc = this.loc, stop = this.stop, values = _c251, header = this.header, lines = _c257);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticPass");
        this.loc.fingerprint(into);
        into.add(this.stop ? 1 : 0);
        into.add(this.values.count);
        for (var _item251 in this.values) {
            var (_t252_0, _t252_1) = _item251;
            into.add_text(_t252_0);
            _t252_1.fingerprint(into);
        }
        if (this.header.is_value()) {
            into.add(this.header.value() as ulong);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.lines.count);
        for (var _item257 in this.lines) {
            var (_t258_0, _t258_1) = _item257;
            _t258_0.fingerprint(into);
            into.add(_t258_1 as ulong);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["loc"] = this.loc.to_json();
        out["stop"] = JsonValue.Bool(this.stop);
        var _v251 = JsonValue.array();
        for (var _item251 in this.values) {
            var _v252 = JsonValue.array();
            var _t252 = _item251;
            var (_t252_0, _t252_1) = _t252;
            _v252.append(JsonValue.String(_t252_0));
            _v252.append(_t252_1.to_json());
            _v251.append(_v252);
        }
        out["values"] = _v251;
        out["header"] = (this.header.is_value() ? JsonValue.Integer(this.header.value() as long) : JsonValue.Null);
        var _v257 = JsonValue.array();
        for (var _item257 in this.lines) {
            var _v258 = JsonValue.array();
            var _t258 = _item257;
            var (_t258_0, _t258_1) = _t258;
            _v258.append(_t258_0.to_json());
            _v258.append(JsonValue.Integer(_t258_1 as long));
            _v257.append(_v258);
        }
        out["lines"] = _v257;
        return out;
    }
}

## `StaticConstant`, a type of the sema model.
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

## The fields of `StaticConstant.Record`.
export struct RecordStaticConstant {
    var name: String;
    var fields: Array<(String, StaticConstant)>;

    construct(name: String = "", fields: Array<(String, StaticConstant)> = Array<(String, StaticConstant)>()) {
        this.name = name;
        this.fields = fields;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): RecordStaticConstant {
        var _c262 = Array<(String, StaticConstant)>();
        for (var _item262 in this.fields) {
            var (_t263_0, _t263_1) = _item262;
            _c262.append((_t263_0, _t263_1.copy()));
        }
        return RecordStaticConstant(name = this.name, fields = _c262);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("RecordStaticConstant");
        into.add_text(this.name);
        into.add(this.fields.count);
        for (var _item262 in this.fields) {
            var (_t263_0, _t263_1) = _item262;
            into.add_text(_t263_0);
            _t263_1.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v262 = JsonValue.array();
        for (var _item262 in this.fields) {
            var _v263 = JsonValue.array();
            var _t263 = _item262;
            var (_t263_0, _t263_1) = _t263;
            _v263.append(JsonValue.String(_t263_0));
            _v263.append(_t263_1.to_json());
            _v262.append(_v263);
        }
        out["fields"] = _v262;
        return out;
    }
}

## `StaticBlock`, a type of the sema model.
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
        var _c272 = Array<StaticItem>();
        for (var _item272 in this.items) {
            _c272.append(_item272.copy());
        }
        var _c274 = Array<(String, TypeName)>();
        for (var _item274 in this.type_map) {
            var (_t275_0, _t275_1) = _item274;
            _c274.append((_t275_0, _t275_1.copy()));
        }
        return StaticBlock(
            captures = this.captures.copy(), items = _c272, type_map = _c274, loc = this.loc, span = this.span
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("StaticBlock");
        into.add(this.captures.count);
        for (var _item270 in this.captures) {
            into.add_text(_item270);
        }
        into.add(this.items.count);
        for (var _item272 in this.items) {
            _item272.fingerprint(into);
        }
        into.add(this.type_map.count);
        for (var _item274 in this.type_map) {
            var (_t275_0, _t275_1) = _item274;
            into.add_text(_t275_0);
            _t275_1.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v270 = JsonValue.array();
        for (var _item270 in this.captures) {
            _v270.append(JsonValue.String(_item270));
        }
        out["captures"] = _v270;
        var _v272 = JsonValue.array();
        for (var _item272 in this.items) {
            _v272.append(_item272.to_json());
        }
        out["items"] = _v272;
        var _v274 = JsonValue.array();
        for (var _item274 in this.type_map) {
            var _v275 = JsonValue.array();
            var _t275 = _item274;
            var (_t275_0, _t275_1) = _t275;
            _v275.append(JsonValue.String(_t275_0));
            _v275.append(_t275_1.to_json());
            _v274.append(_v275);
        }
        out["type_map"] = _v274;
        out["loc"] = this.loc.to_json();
        out["span"] = this.span.to_json();
        return out;
    }
}

## `ModuleStaticBlock`, a type of the sema model.
export struct ModuleStaticBlock {
    var block: StaticBlock;
    var constants: Array<(String, Loc)>;

    construct(block: StaticBlock = StaticBlock(), constants: Array<(String, Loc)> = Array<(String, Loc)>()) {
        this.block = block;
        this.constants = constants;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): ModuleStaticBlock {
        var _c281 = Array<(String, Loc)>();
        for (var _item281 in this.constants) {
            var (_t282_0, _t282_1) = _item281;
            _c281.append((_t282_0, _t282_1));
        }
        return ModuleStaticBlock(block = this.block.copy(), constants = _c281);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ModuleStaticBlock");
        this.block.fingerprint(into);
        into.add(this.constants.count);
        for (var _item281 in this.constants) {
            var (_t282_0, _t282_1) = _item281;
            into.add_text(_t282_0);
            _t282_1.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["block"] = this.block.to_json();
        var _v281 = JsonValue.array();
        for (var _item281 in this.constants) {
            var _v282 = JsonValue.array();
            var _t282 = _item281;
            var (_t282_0, _t282_1) = _t282;
            _v282.append(JsonValue.String(_t282_0));
            _v282.append(_t282_1.to_json());
            _v281.append(_v282);
        }
        out["constants"] = _v281;
        return out;
    }
}

## `StaticItem`, a type of the sema model.
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
                for (var _item311 in value) {
                    _item311.fingerprint(into);
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
                var _c311 = Array<StaticItem>();
                for (var _item311 in value) {
                    _c311.append(_item311.copy());
                }
                return StaticItem.Block(_c311);
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
                var _v311 = JsonValue.array();
                for (var _item311 in value) {
                    _v311.append(_item311.to_json());
                }
                return _tagged("Block", _v311);
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

## The fields of `StaticItem.For`.
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
        var _c287 = Array<StaticItem>();
        for (var _item287 in this.body) {
            _c287.append(_item287.copy());
        }
        return ForStaticItem(name = this.name, iterable = this.iterable, body = _c287, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ForStaticItem");
        into.add_text(this.name);
        into.add(this.body.count);
        for (var _item287 in this.body) {
            _item287.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["iterable"] = this.iterable.to_json();
        var _v287 = JsonValue.array();
        for (var _item287 in this.body) {
            _v287.append(_item287.to_json());
        }
        out["body"] = _v287;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem.While`.
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
        var _c291 = Array<StaticItem>();
        for (var _item291 in this.body) {
            _c291.append(_item291.copy());
        }
        return WhileStaticItem(condition = this.condition, body = _c291, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("WhileStaticItem");
        into.add(this.body.count);
        for (var _item291 in this.body) {
            _item291.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v291 = JsonValue.array();
        for (var _item291 in this.body) {
            _v291.append(_item291.to_json());
        }
        out["body"] = _v291;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem.Jump`.
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

## The fields of `StaticItem.If`.
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
        var _c297 = Array<StaticItem>();
        for (var _item297 in this.then_items) {
            _c297.append(_item297.copy());
        }
        var _c299 = Array<StaticItem>();
        for (var _item299 in this.else_items) {
            _c299.append(_item299.copy());
        }
        return IfStaticItem(condition = this.condition, then_items = _c297, else_items = _c299, loc = this.loc);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("IfStaticItem");
        into.add(this.then_items.count);
        for (var _item297 in this.then_items) {
            _item297.fingerprint(into);
        }
        into.add(this.else_items.count);
        for (var _item299 in this.else_items) {
            _item299.fingerprint(into);
        }
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v297 = JsonValue.array();
        for (var _item297 in this.then_items) {
            _v297.append(_item297.to_json());
        }
        out["then_items"] = _v297;
        var _v299 = JsonValue.array();
        for (var _item299 in this.else_items) {
            _v299.append(_item299.to_json());
        }
        out["else_items"] = _v299;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## The fields of `StaticItem.EmitIf`.
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
        var _c303 = Array<StaticItem>();
        for (var _item303 in this.then_items) {
            _c303.append(_item303.copy());
        }
        var _c305 = Array<StaticItem>();
        for (var _item305 in this.else_items) {
            _c305.append(_item305.copy());
        }
        return EmitIfStaticItem(
            condition = this.condition.copy(), then_items = _c303, else_items = _c305, span = this.span
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("EmitIfStaticItem");
        this.condition.fingerprint(into);
        into.add(this.then_items.count);
        for (var _item303 in this.then_items) {
            _item303.fingerprint(into);
        }
        into.add(this.else_items.count);
        for (var _item305 in this.else_items) {
            _item305.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["condition"] = this.condition.to_json();
        var _v303 = JsonValue.array();
        for (var _item303 in this.then_items) {
            _v303.append(_item303.to_json());
        }
        out["then_items"] = _v303;
        var _v305 = JsonValue.array();
        for (var _item305 in this.else_items) {
            _v305.append(_item305.to_json());
        }
        out["else_items"] = _v305;
        out["span"] = this.span.to_json();
        return out;
    }
}

## The fields of `StaticItem.Var`.
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

## `VariableDef`, a type of the sema model.
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
        var _c318 = Optional<Expression>.Empty;
        if (this.default.is_value()) {
            _c318 = Optional<Expression>.Value(this.default.value().copy());
        }
        return VariableDef(
            name = this.name,
            ty = this.ty.copy(),
            default = _c318,
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
        for (var _item322 in this.attributes) {}
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
        var _v322 = JsonValue.array();
        for (var _item322 in this.attributes) {
            _v322.append(_item322.to_json());
        }
        out["attributes"] = _v322;
        out["loc"] = this.loc.to_json();
        out["type_loc"] = this.type_loc.to_json();
        out["is_const"] = JsonValue.Bool(this.is_const);
        return out;
    }
}

## `GenericParam`, a type of the sema model.
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
        var _c329 = Array<Bound>();
        for (var _item329 in this.bounds) {
            _c329.append(_item329.copy());
        }
        var _c331 = Optional<TypeName>.Empty;
        if (this.default.is_value()) {
            _c331 = Optional<TypeName>.Value(this.default.value().copy());
        }
        return GenericParam(
            name = this.name,
            loc = this.loc,
            bounds = _c329,
            default = _c331,
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
        for (var _item329 in this.bounds) {
            _item329.fingerprint(into);
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
        var _v329 = JsonValue.array();
        for (var _item329 in this.bounds) {
            _v329.append(_item329.to_json());
        }
        out["bounds"] = _v329;
        out["default"] = (this.default.is_value() ? this.default.value().to_json() : JsonValue.Null);
        out["default_loc"] = this.default_loc.to_json();
        out["is_argument"] = JsonValue.Bool(this.is_argument);
        return out;
    }
}

## `Bound`, a type of the sema model.
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

## `Withheld`, a type of the sema model.
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

## `TypeUse`, a type of the sema model.
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
        for (var _item345 in this.args) {
            _item345.fingerprint(into);
        }
        into.add(this.context as ulong);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        var _v345 = JsonValue.array();
        for (var _item345 in this.args) {
            _v345.append(_item345.to_json());
        }
        out["args"] = _v345;
        out["context"] = unsigned_json(this.context);
        return out;
    }
}

## `UseContext`, a type of the sema model.
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
        var _c348 = Array<GenericParam>();
        for (var _item348 in this.scope) {
            _c348.append(_item348.copy());
        }
        var _c350 = Optional<TypeName>.Empty;
        if (this.extension.is_value()) {
            _c350 = Optional<TypeName>.Value(this.extension.value().copy());
        }
        return UseContext(scope = _c348, extension = _c350, conditions = this.conditions.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("UseContext");
        into.add(this.scope.count);
        for (var _item348 in this.scope) {
            _item348.fingerprint(into);
        }
        if (this.extension.is_value()) {
            this.extension.value().fingerprint(into);
            into.add(1);
        } else {
            into.add(0);
        }
        into.add(this.conditions.count);
        for (var _item352 in this.conditions) {}
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v348 = JsonValue.array();
        for (var _item348 in this.scope) {
            _v348.append(_item348.to_json());
        }
        out["scope"] = _v348;
        out["extension"] = (this.extension.is_value() ? this.extension.value().to_json() : JsonValue.Null);
        var _v352 = JsonValue.array();
        for (var _item352 in this.conditions) {
            _v352.append(_item352.to_json());
        }
        out["conditions"] = _v352;
        return out;
    }
}

## `FunctionDef`, a type of the sema model.
export struct FunctionDef {
    ## In memory only: kept by `copy()`, not fingerprinted, written as
    ## JSON or recorded.
    var pending_body: PendingBody? = Optional<PendingBody>.Empty;
    ## In memory only, and not kept by `copy()`: the body as the record
    ## it was read from wrote it, which hashing a delta's base or an own
    ## interface uses in place of the body, decoded or not: checked
    ## bodies don't change, and decoding one is no change. A copy, such
    ## as a specialization, gets a body of its own.
    var body_origin: PendingBody? = Optional<PendingBody>.Empty;
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
        var _c356 = Array<GenericParam>();
        for (var _item356 in this.generic_params) {
            _c356.append(_item356.copy());
        }
        var _c358 = Array<VariableDef>();
        for (var _item358 in this.parameters) {
            _c358.append(_item358.copy());
        }
        var _c360 = Optional<Block>.Empty;
        if (this.body.is_value()) {
            _c360 = Optional<Block>.Value(this.body.value().copy());
        }
        var _c370 = Optional<Array<String>>.Empty;
        if (this.trait_default.is_value()) {
            _c370 = Optional<Array<String>>.Value(this.trait_default.value().copy());
        }
        var _copy = FunctionDef(
            name = this.name,
            ty = this.ty.copy(),
            generic_params = _c356,
            parameters = _c358,
            body = _c360,
            parent = this.parent,
            is_static = this.is_static,
            is_indexer = this.is_indexer,
            is_generic_func = this.is_generic_func,
            attributes = this.attributes.copy(),
            loc = this.loc,
            trait_default = _c370,
            owner = this.owner
        );
        _copy.pending_body = this.pending_body;
        return _copy;
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("FunctionDef");
        into.add_text(this.name);
        this.ty.fingerprint(into);
        into.add(this.generic_params.count);
        for (var _item356 in this.generic_params) {
            _item356.fingerprint(into);
        }
        into.add(this.parameters.count);
        for (var _item358 in this.parameters) {
            _item358.fingerprint(into);
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
        for (var _item367 in this.attributes) {}
        this.loc.fingerprint(into);
        if (this.trait_default.is_value()) {
            into.add(this.trait_default.value().count);
            for (var _item371 in this.trait_default.value()) {
                into.add_text(_item371);
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
        var _v356 = JsonValue.array();
        for (var _item356 in this.generic_params) {
            _v356.append(_item356.to_json());
        }
        out["generic_params"] = _v356;
        var _v358 = JsonValue.array();
        for (var _item358 in this.parameters) {
            _v358.append(_item358.to_json());
        }
        out["parameters"] = _v358;
        out["body"] = (this.body.is_value() ? this.body.value().to_json() : JsonValue.Null);
        out["parent"] = (this.parent.is_value() ? JsonValue.String(this.parent.value()) : JsonValue.Null);
        out["is_static"] = JsonValue.Bool(this.is_static);
        out["is_indexer"] = JsonValue.Bool(this.is_indexer);
        out["is_generic_func"] = JsonValue.Bool(this.is_generic_func);
        var _v367 = JsonValue.array();
        for (var _item367 in this.attributes) {
            _v367.append(_item367.to_json());
        }
        out["attributes"] = _v367;
        out["loc"] = this.loc.to_json();
        var _v370 = JsonValue.Null;
        if (this.trait_default.is_value()) {
            var _v371 = JsonValue.array();
            for (var _item371 in this.trait_default.value()) {
                _v371.append(JsonValue.String(_item371));
            }
            _v370 = _v371;
        }
        out["trait_default"] = _v370;
        out["owner"] = this.owner.to_json();
        return out;
    }
}

## `StructDef`, a type of the sema model.
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
        var _c376 = Array<GenericParam>();
        for (var _item376 in this.generic_params) {
            _c376.append(_item376.copy());
        }
        var _c378 = Array<VariableDef>();
        for (var _item378 in this.field_members) {
            _c378.append(_item378.copy());
        }
        var _c380 = Array<FunctionDef>();
        for (var _item380 in this.method_members) {
            _c380.append(_item380.copy());
        }
        var _c382 = Array<FunctionDef>();
        for (var _item382 in this.generic_methods) {
            _c382.append(_item382.copy());
        }
        var _c384 = Array<FunctionDef>();
        for (var _item384 in this.constructors) {
            _c384.append(_item384.copy());
        }
        var _c389 = Array<TypeName>();
        for (var _item389 in this.traits) {
            _c389.append(_item389.copy());
        }
        var _c394 = Optional<Array<EnumCaseDef>>.Empty;
        if (this.enum_cases.is_value()) {
            var _c395 = Array<EnumCaseDef>();
            for (var _item395 in this.enum_cases.value()) {
                _c395.append(_item395.copy());
            }
            _c394 = Optional<Array<EnumCaseDef>>.Value(_c395);
        }
        return StructDef(
            name = this.name,
            ty = this.ty.copy(),
            generic_params = _c376,
            field_members = _c378,
            method_members = _c380,
            generic_methods = _c382,
            constructors = _c384,
            destructor = this.destructor.copy(),
            acquire = this.acquire.copy(),
            release = this.release.copy(),
            traits = _c389,
            attributes = this.attributes.copy(),
            loc = this.loc,
            enum_cases = _c394
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
        for (var _item376 in this.generic_params) {
            _item376.fingerprint(into);
        }
        into.add(this.field_members.count);
        for (var _item378 in this.field_members) {
            _item378.fingerprint(into);
        }
        into.add(this.method_members.count);
        for (var _item380 in this.method_members) {
            _item380.fingerprint(into);
        }
        into.add(this.generic_methods.count);
        for (var _item382 in this.generic_methods) {
            _item382.fingerprint(into);
        }
        into.add(this.constructors.count);
        for (var _item384 in this.constructors) {
            _item384.fingerprint(into);
        }
        this.destructor.fingerprint(into);
        this.acquire.fingerprint(into);
        this.release.fingerprint(into);
        into.add(this.traits.count);
        for (var _item389 in this.traits) {
            _item389.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item391 in this.attributes) {}
        this.loc.fingerprint(into);
        if (this.enum_cases.is_value()) {
            into.add(this.enum_cases.value().count);
            for (var _item395 in this.enum_cases.value()) {
                _item395.fingerprint(into);
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
        var _v376 = JsonValue.array();
        for (var _item376 in this.generic_params) {
            _v376.append(_item376.to_json());
        }
        out["generic_params"] = _v376;
        var _v378 = JsonValue.array();
        for (var _item378 in this.field_members) {
            _v378.append(_item378.to_json());
        }
        out["field_members"] = _v378;
        var _v380 = JsonValue.array();
        for (var _item380 in this.method_members) {
            _v380.append(_item380.to_json());
        }
        out["method_members"] = _v380;
        var _v382 = JsonValue.array();
        for (var _item382 in this.generic_methods) {
            _v382.append(_item382.to_json());
        }
        out["generic_methods"] = _v382;
        var _v384 = JsonValue.array();
        for (var _item384 in this.constructors) {
            _v384.append(_item384.to_json());
        }
        out["constructors"] = _v384;
        out["destructor"] = this.destructor.to_json();
        out["acquire"] = this.acquire.to_json();
        out["release"] = this.release.to_json();
        var _v389 = JsonValue.array();
        for (var _item389 in this.traits) {
            _v389.append(_item389.to_json());
        }
        out["traits"] = _v389;
        var _v391 = JsonValue.array();
        for (var _item391 in this.attributes) {
            _v391.append(_item391.to_json());
        }
        out["attributes"] = _v391;
        out["loc"] = this.loc.to_json();
        var _v394 = JsonValue.Null;
        if (this.enum_cases.is_value()) {
            var _v395 = JsonValue.array();
            for (var _item395 in this.enum_cases.value()) {
                _v395.append(_item395.to_json());
            }
            _v394 = _v395;
        }
        out["enum_cases"] = _v394;
        return out;
    }
}

## `AccessorKind`, a type of the sema model.
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

## `PropertyDef`, a type of the sema model.
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

## `Conversion`, a type of the sema model.
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

## `TraitDef`, a type of the sema model.
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
        var _c413 = Array<GenericParam>();
        for (var _item413 in this.generic_params) {
            _c413.append(_item413.copy());
        }
        var _c415 = Array<FunctionDef>();
        for (var _item415 in this.methods) {
            _c415.append(_item415.copy());
        }
        return TraitDef(
            name = this.name,
            generic_params = _c413,
            methods = _c415,
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
        for (var _item413 in this.generic_params) {
            _item413.fingerprint(into);
        }
        into.add(this.methods.count);
        for (var _item415 in this.methods) {
            _item415.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item417 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v413 = JsonValue.array();
        for (var _item413 in this.generic_params) {
            _v413.append(_item413.to_json());
        }
        out["generic_params"] = _v413;
        var _v415 = JsonValue.array();
        for (var _item415 in this.methods) {
            _v415.append(_item415.to_json());
        }
        out["methods"] = _v415;
        var _v417 = JsonValue.array();
        for (var _item417 in this.attributes) {
            _v417.append(_item417.to_json());
        }
        out["attributes"] = _v417;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `TraitType`, a type of the sema model.
export struct TraitType {
    var ty: TypeName;
    var methods: Array<FunctionDef>;

    construct(ty: TypeName = TypeName(), methods: Array<FunctionDef> = Array<FunctionDef>()) {
        this.ty = ty;
        this.methods = methods;
    }

    ## Returns a deep copy, which shares only locations and AST nodes.
    copy(): TraitType {
        var _c421 = Array<FunctionDef>();
        for (var _item421 in this.methods) {
            _c421.append(_item421.copy());
        }
        return TraitType(ty = this.ty.copy(), methods = _c421);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TraitType");
        this.ty.fingerprint(into);
        into.add(this.methods.count);
        for (var _item421 in this.methods) {
            _item421.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["ty"] = this.ty.to_json();
        var _v421 = JsonValue.array();
        for (var _item421 in this.methods) {
            _v421.append(_item421.to_json());
        }
        out["methods"] = _v421;
        return out;
    }
}

## `ExtensionDef`, a type of the sema model.
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
        var _c426 = Array<TypeName>();
        for (var _item426 in this.traits) {
            _c426.append(_item426.copy());
        }
        var _c428 = Array<(ulong, Bound)>();
        for (var _item428 in this.restated) {
            var (_t429_0, _t429_1) = _item428;
            _c428.append((_t429_0, _t429_1.copy()));
        }
        var _c432 = Array<FunctionDef>();
        for (var _item432 in this.methods) {
            _c432.append(_item432.copy());
        }
        return ExtensionDef(
            target = this.target.copy(),
            resolved = this.resolved,
            traits = _c426,
            restated = _c428,
            methods = _c432,
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
        for (var _item426 in this.traits) {
            _item426.fingerprint(into);
        }
        into.add(this.restated.count);
        for (var _item428 in this.restated) {
            var (_t429_0, _t429_1) = _item428;
            into.add(_t429_0 as ulong);
            _t429_1.fingerprint(into);
        }
        into.add(this.methods.count);
        for (var _item432 in this.methods) {
            _item432.fingerprint(into);
        }
        into.add(this.attributes.count);
        for (var _item434 in this.attributes) {}
        this.loc.fingerprint(into);
        into.add(this.is_exported ? 1 : 0);
        into.add(this.is_private ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["target"] = this.target.to_json();
        out["resolved"] = (this.resolved.is_value() ? JsonValue.String(this.resolved.value()) : JsonValue.Null);
        var _v426 = JsonValue.array();
        for (var _item426 in this.traits) {
            _v426.append(_item426.to_json());
        }
        out["traits"] = _v426;
        var _v428 = JsonValue.array();
        for (var _item428 in this.restated) {
            var _v429 = JsonValue.array();
            var _t429 = _item428;
            var (_t429_0, _t429_1) = _t429;
            _v429.append(unsigned_json(_t429_0));
            _v429.append(_t429_1.to_json());
            _v428.append(_v429);
        }
        out["restated"] = _v428;
        var _v432 = JsonValue.array();
        for (var _item432 in this.methods) {
            _v432.append(_item432.to_json());
        }
        out["methods"] = _v432;
        var _v434 = JsonValue.array();
        for (var _item434 in this.attributes) {
            _v434.append(_item434.to_json());
        }
        out["attributes"] = _v434;
        out["loc"] = this.loc.to_json();
        out["is_exported"] = JsonValue.Bool(this.is_exported);
        out["is_private"] = JsonValue.Bool(this.is_private);
        return out;
    }
}

## `ExtensionScopes`, a type of the sema model.
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
        var _c441 = Array<HashSet<uint>>();
        for (var _item441 in this.visible) {
            _c441.append(_item441.copy());
        }
        return ExtensionScopes(prelude = this.prelude.copy(), visible = _c441, module = this.module.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("ExtensionScopes");
        into.add(this.prelude.count);
        for (var _item439 in this.prelude) {
            into.add(_item439 as ulong);
        }
        into.add(this.visible.count);
        for (var _item441 in this.visible) {
            into.add(_item441.count);
            for (var _item442 in _item441) {
                into.add(_item442 as ulong);
            }
        }
        into.add(this.module.count);
        for (var _item444 in this.module) {
            if (_item444.is_value()) {
                into.add(_item444.value() as ulong);
                into.add(1);
            } else {
                into.add(0);
            }
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v439 = JsonValue.array();
        for (var _item439 in this.prelude) {
            _v439.append(JsonValue.Integer(_item439 as long));
        }
        out["prelude"] = _v439;
        var _v441 = JsonValue.array();
        for (var _item441 in this.visible) {
            var _v442 = JsonValue.array();
            for (var _item442 in _item441) {
                _v442.append(JsonValue.Integer(_item442 as long));
            }
            _v441.append(_v442);
        }
        out["visible"] = _v441;
        var _v444 = JsonValue.array();
        for (var _item444 in this.module) {
            _v444.append((_item444.is_value() ? JsonValue.Integer(_item444.value() as long) : JsonValue.Null));
        }
        out["module"] = _v444;
        return out;
    }
}

## `ExternDef`, a type of the sema model.
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
        var _c449 = Array<VariableDef>();
        for (var _item449 in this.parameters) {
            _c449.append(_item449.copy());
        }
        return ExternDef(
            name = this.name,
            ty = this.ty.copy(),
            parameters = _c449,
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
        for (var _item449 in this.parameters) {
            _item449.fingerprint(into);
        }
        into.add(this.is_variadic ? 1 : 0);
        into.add(this.attributes.count);
        for (var _item452 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        out["ty"] = this.ty.to_json();
        var _v449 = JsonValue.array();
        for (var _item449 in this.parameters) {
            _v449.append(_item449.to_json());
        }
        out["parameters"] = _v449;
        out["is_variadic"] = JsonValue.Bool(this.is_variadic);
        var _v452 = JsonValue.array();
        for (var _item452 in this.attributes) {
            _v452.append(_item452.to_json());
        }
        out["attributes"] = _v452;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `TypeAliasDef`, a type of the sema model.
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
        var _c456 = Array<GenericParam>();
        for (var _item456 in this.generic_params) {
            _c456.append(_item456.copy());
        }
        return TypeAliasDef(
            name = this.name,
            generic_params = _c456,
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
        for (var _item456 in this.generic_params) {
            _item456.fingerprint(into);
        }
        this.target.fingerprint(into);
        into.add(this.attributes.count);
        for (var _item459 in this.attributes) {}
        this.loc.fingerprint(into);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v456 = JsonValue.array();
        for (var _item456 in this.generic_params) {
            _v456.append(_item456.to_json());
        }
        out["generic_params"] = _v456;
        out["target"] = this.target.to_json();
        var _v459 = JsonValue.array();
        for (var _item459 in this.attributes) {
            _v459.append(_item459.to_json());
        }
        out["attributes"] = _v459;
        out["loc"] = this.loc.to_json();
        return out;
    }
}

## `Declaration`, a type of the sema model.
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

## `Module`, a type of the sema model.
export struct Module {
    ## In memory only: kept by `copy()`, not fingerprinted, written as
    ## JSON or recorded.
    var own_decls: UnitDecls? = Optional<UnitDecls>.Empty;
    ## In memory only: kept by `copy()`, not fingerprinted, written as
    ## JSON or recorded.
    var extended_checked: HashSet<String> = HashSet<String>();
    ## In memory only: kept by `copy()`, not fingerprinted, written as
    ## JSON or recorded.
    var field_lists_read: HashSet<String> = HashSet<String>();
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
        var _c471 = Array<StructDef>();
        for (var _item471 in this.structs) {
            _c471.append(_item471.copy());
        }
        var _c473 = Array<TraitDef>();
        for (var _item473 in this.traits) {
            _c473.append(_item473.copy());
        }
        var _c475 = Array<ExtensionDef>();
        for (var _item475 in this.extensions) {
            _c475.append(_item475.copy());
        }
        var _c477 = Array<FunctionDef>();
        for (var _item477 in this.functions) {
            _c477.append(_item477.copy());
        }
        var _c479 = Array<ExternDef>();
        for (var _item479 in this.externs) {
            _c479.append(_item479.copy());
        }
        var _c481 = Array<VariableDef>();
        for (var _item481 in this.globals) {
            _c481.append(_item481.copy());
        }
        var _c483 = Array<ModuleStaticBlock>();
        for (var _item483 in this.static_blocks) {
            _c483.append(_item483.copy());
        }
        var _c485 = Array<EnumDef>();
        for (var _item485 in this.enums) {
            _c485.append(_item485.copy());
        }
        var _c487 = Array<TypeName>();
        for (var _item487 in this.struct_specs) {
            _c487.append(_item487.copy());
        }
        var _c489 = Array<TypeName>();
        for (var _item489 in this.func_specs) {
            _c489.append(_item489.copy());
        }
        var _c491 = Array<TypeAliasDef>();
        for (var _item491 in this.type_aliases) {
            _c491.append(_item491.copy());
        }
        var _c493 = Array<Withheld>();
        for (var _item493 in this.withheld) {
            _c493.append(_item493.copy());
        }
        var _c495 = Array<PropertyDef>();
        for (var _item495 in this.properties) {
            _c495.append(_item495.copy());
        }
        var _c497 = Array<TypeUse>();
        for (var _item497 in this.type_uses) {
            _c497.append(_item497.copy());
        }
        var _c499 = Array<UseContext>();
        for (var _item499 in this.use_contexts) {
            _c499.append(_item499.copy());
        }
        var _c501 = Array<(Loc, ulong, Loc)>();
        for (var _item501 in this.literal_args) {
            var (_t502_0, _t502_1, _t502_2) = _item501;
            _c501.append((_t502_0, _t502_1, _t502_2));
        }
        var _c506 = Array<TypeAliasDef>();
        for (var _item506 in this.constrained_aliases) {
            _c506.append(_item506.copy());
        }
        var _c508 = Array<TraitType>();
        for (var _item508 in this.trait_types) {
            _c508.append(_item508.copy());
        }
        var _c510 = Array<Conversion>();
        for (var _item510 in this.conversions) {
            _c510.append(_item510.copy());
        }
        var _c512 = Map<String, Array<String>>();
        for (var (_key512, _item512) in this.overload_sets) {
            _c512[_key512] = _item512.copy();
        }
        var _c515 = Map<String, Array<Array<String>>>();
        for (var (_key515, _item515) in this.overload_unions) {
            var _c516 = Array<Array<String>>();
            for (var _item516 in _item515) {
                _c516.append(_item516.copy());
            }
            _c515[_key515] = _c516;
        }
        var _c519 = Map<String, Map<String, Array<String>>>();
        for (var (_key519, _item519) in this.method_overload_sets) {
            var _c520 = Map<String, Array<String>>();
            for (var (_key520, _item520) in _item519) {
                _c520[_key520] = _item520.copy();
            }
            _c519[_key519] = _c520;
        }
        var _c528 = Array<(Loc, String)>();
        for (var _item528 in this.call_targets) {
            var (_t529_0, _t529_1) = _item528;
            _c528.append((_t529_0, _t529_1));
        }
        var _c532 = Array<(Loc, String)>();
        for (var _item532 in this.argument_names) {
            var (_t533_0, _t533_1) = _item532;
            _c532.append((_t533_0, _t533_1));
        }
        var _c540 = HashMap<Loc, String>();
        for (var (_key540, _item540) in this.recorded_summaries) {
            _c540[_key540] = _item540;
        }
        var _c546 = HashMap<String, SpecRequest>();
        for (var (_key546, _item546) in this.spec_requests) {
            _c546[_key546] = _item546.copy();
        }
        var _c549 = Array<(Loc, String)>();
        for (var _item549 in this.summaries_to_record) {
            var (_t550_0, _t550_1) = _item549;
            _c549.append((_t550_0, _t550_1));
        }
        var _c553 = HashMap<String, Array<bool>>();
        for (var (_key553, _item553) in this.caller_copies) {
            _c553[_key553] = _item553.copy();
        }
        var _copy = Module(
            imports = this.imports.copy(),
            structs = _c471,
            traits = _c473,
            extensions = _c475,
            functions = _c477,
            externs = _c479,
            globals = _c481,
            static_blocks = _c483,
            enums = _c485,
            struct_specs = _c487,
            func_specs = _c489,
            type_aliases = _c491,
            withheld = _c493,
            properties = _c495,
            type_uses = _c497,
            use_contexts = _c499,
            literal_args = _c501,
            constrained_aliases = _c506,
            trait_types = _c508,
            conversions = _c510,
            overload_sets = _c512,
            overload_unions = _c515,
            method_overload_sets = _c519,
            extension_scopes = this.extension_scopes.copy(),
            private_functions = this.private_functions.copy(),
            file_private_functions = this.file_private_functions.copy(),
            call_targets = _c528,
            argument_names = _c532,
            namespaces = this.namespaces.copy(),
            cached_files = this.cached_files.copy(),
            recorded_summaries = _c540,
            stripped = this.stripped.copy(),
            templates = this.templates.copy(),
            checked = this.checked.copy(),
            spec_requests = _c546,
            record_summaries = this.record_summaries,
            summaries_to_record = _c549,
            caller_copies = _c553,
            linked = this.linked
        );
        _copy.own_decls = this.own_decls;
        _copy.extended_checked = this.extended_checked;
        _copy.field_lists_read = this.field_lists_read;
        return _copy;
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Module");
        into.add(this.imports.count);
        for (var _item469 in this.imports) {}
        into.add(this.structs.count);
        for (var _item471 in this.structs) {
            _item471.fingerprint(into);
        }
        into.add(this.traits.count);
        for (var _item473 in this.traits) {
            _item473.fingerprint(into);
        }
        into.add(this.extensions.count);
        for (var _item475 in this.extensions) {
            _item475.fingerprint(into);
        }
        into.add(this.functions.count);
        for (var _item477 in this.functions) {
            _item477.fingerprint(into);
        }
        into.add(this.externs.count);
        for (var _item479 in this.externs) {
            _item479.fingerprint(into);
        }
        into.add(this.globals.count);
        for (var _item481 in this.globals) {
            _item481.fingerprint(into);
        }
        into.add(this.static_blocks.count);
        for (var _item483 in this.static_blocks) {
            _item483.fingerprint(into);
        }
        into.add(this.enums.count);
        for (var _item485 in this.enums) {
            _item485.fingerprint(into);
        }
        into.add(this.struct_specs.count);
        for (var _item487 in this.struct_specs) {
            _item487.fingerprint(into);
        }
        into.add(this.func_specs.count);
        for (var _item489 in this.func_specs) {
            _item489.fingerprint(into);
        }
        into.add(this.type_aliases.count);
        for (var _item491 in this.type_aliases) {
            _item491.fingerprint(into);
        }
        into.add(this.withheld.count);
        for (var _item493 in this.withheld) {
            _item493.fingerprint(into);
        }
        into.add(this.properties.count);
        for (var _item495 in this.properties) {
            _item495.fingerprint(into);
        }
        into.add(this.type_uses.count);
        for (var _item497 in this.type_uses) {
            _item497.fingerprint(into);
        }
        into.add(this.use_contexts.count);
        for (var _item499 in this.use_contexts) {
            _item499.fingerprint(into);
        }
        into.add(this.literal_args.count);
        for (var _item501 in this.literal_args) {
            var (_t502_0, _t502_1, _t502_2) = _item501;
            _t502_0.fingerprint(into);
            into.add(_t502_1 as ulong);
            _t502_2.fingerprint(into);
        }
        into.add(this.constrained_aliases.count);
        for (var _item506 in this.constrained_aliases) {
            _item506.fingerprint(into);
        }
        into.add(this.trait_types.count);
        for (var _item508 in this.trait_types) {
            _item508.fingerprint(into);
        }
        into.add(this.conversions.count);
        for (var _item510 in this.conversions) {
            _item510.fingerprint(into);
        }
        into.add(this.overload_sets.count);
        for (var (_key512, _item512) in this.overload_sets) {
            into.add_text(_key512);
            into.add(_item512.count);
            for (var _item514 in _item512) {
                into.add_text(_item514);
            }
        }
        into.add(this.overload_unions.count);
        for (var (_key516, _item516) in this.overload_unions) {
            into.add_text(_key516);
            into.add(_item516.count);
            for (var _item518 in _item516) {
                into.add(_item518.count);
                for (var _item519 in _item518) {
                    into.add_text(_item519);
                }
            }
        }
        into.add(this.method_overload_sets.count);
        for (var (_key521, _item521) in this.method_overload_sets) {
            into.add_text(_key521);
            into.add(_item521.count);
            for (var (_key523, _item523) in _item521) {
                into.add_text(_key523);
                into.add(_item523.count);
                for (var _item525 in _item523) {
                    into.add_text(_item525);
                }
            }
        }
        this.extension_scopes.fingerprint(into);
        into.add(this.private_functions.count);
        for (var _item528 in this.private_functions) {
            _item528.fingerprint(into);
        }
        into.add(this.file_private_functions.count);
        for (var _item530 in this.file_private_functions) {
            _item530.fingerprint(into);
        }
        into.add(this.call_targets.count);
        for (var _item532 in this.call_targets) {
            var (_t533_0, _t533_1) = _item532;
            _t533_0.fingerprint(into);
            into.add_text(_t533_1);
        }
        into.add(this.argument_names.count);
        for (var _item536 in this.argument_names) {
            var (_t537_0, _t537_1) = _item536;
            _t537_0.fingerprint(into);
            into.add_text(_t537_1);
        }
        into.add(this.namespaces.count);
        for (var _item540 in this.namespaces) {
            into.add_text(_item540);
        }
        into.add(this.cached_files.count);
        for (var _item542 in this.cached_files) {
            into.add(_item542 ? 1 : 0);
        }
        into.add(this.recorded_summaries.count);
        for (var (_key544, _item544) in this.recorded_summaries) {
            _key544.fingerprint(into);
            into.add_text(_item544);
        }
        into.add(this.stripped.count);
        for (var _item547 in this.stripped) {
            _item547.fingerprint(into);
        }
        this.templates.fingerprint(into);
        this.checked.fingerprint(into);
        into.add(this.spec_requests.count);
        for (var (_key551, _item551) in this.spec_requests) {
            into.add_text(_key551);
            _item551.fingerprint(into);
        }
        into.add(this.record_summaries ? 1 : 0);
        into.add(this.summaries_to_record.count);
        for (var _item555 in this.summaries_to_record) {
            var (_t556_0, _t556_1) = _item555;
            _t556_0.fingerprint(into);
            into.add_text(_t556_1);
        }
        into.add(this.caller_copies.count);
        for (var (_key559, _item559) in this.caller_copies) {
            into.add_text(_key559);
            into.add(_item559.count);
            for (var _item561 in _item559) {
                into.add(_item561 ? 1 : 0);
            }
        }
        into.add(this.linked ? 1 : 0);
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v469 = JsonValue.array();
        for (var _item469 in this.imports) {
            _v469.append(_item469.to_json());
        }
        out["imports"] = _v469;
        var _v471 = JsonValue.array();
        for (var _item471 in this.structs) {
            _v471.append(_item471.to_json());
        }
        out["structs"] = _v471;
        var _v473 = JsonValue.array();
        for (var _item473 in this.traits) {
            _v473.append(_item473.to_json());
        }
        out["traits"] = _v473;
        var _v475 = JsonValue.array();
        for (var _item475 in this.extensions) {
            _v475.append(_item475.to_json());
        }
        out["extensions"] = _v475;
        var _v477 = JsonValue.array();
        for (var _item477 in this.functions) {
            _v477.append(_item477.to_json());
        }
        out["functions"] = _v477;
        var _v479 = JsonValue.array();
        for (var _item479 in this.externs) {
            _v479.append(_item479.to_json());
        }
        out["externs"] = _v479;
        var _v481 = JsonValue.array();
        for (var _item481 in this.globals) {
            _v481.append(_item481.to_json());
        }
        out["globals"] = _v481;
        var _v483 = JsonValue.array();
        for (var _item483 in this.static_blocks) {
            _v483.append(_item483.to_json());
        }
        out["static_blocks"] = _v483;
        var _v485 = JsonValue.array();
        for (var _item485 in this.enums) {
            _v485.append(_item485.to_json());
        }
        out["enums"] = _v485;
        var _v487 = JsonValue.array();
        for (var _item487 in this.struct_specs) {
            _v487.append(_item487.to_json());
        }
        out["struct_specs"] = _v487;
        var _v489 = JsonValue.array();
        for (var _item489 in this.func_specs) {
            _v489.append(_item489.to_json());
        }
        out["func_specs"] = _v489;
        var _v491 = JsonValue.array();
        for (var _item491 in this.type_aliases) {
            _v491.append(_item491.to_json());
        }
        out["type_aliases"] = _v491;
        var _v493 = JsonValue.array();
        for (var _item493 in this.withheld) {
            _v493.append(_item493.to_json());
        }
        out["withheld"] = _v493;
        var _v495 = JsonValue.array();
        for (var _item495 in this.properties) {
            _v495.append(_item495.to_json());
        }
        out["properties"] = _v495;
        var _v497 = JsonValue.array();
        for (var _item497 in this.type_uses) {
            _v497.append(_item497.to_json());
        }
        out["type_uses"] = _v497;
        var _v499 = JsonValue.array();
        for (var _item499 in this.use_contexts) {
            _v499.append(_item499.to_json());
        }
        out["use_contexts"] = _v499;
        var _v501 = JsonValue.array();
        for (var _item501 in this.literal_args) {
            var _v502 = JsonValue.array();
            var _t502 = _item501;
            var (_t502_0, _t502_1, _t502_2) = _t502;
            _v502.append(_t502_0.to_json());
            _v502.append(unsigned_json(_t502_1));
            _v502.append(_t502_2.to_json());
            _v501.append(_v502);
        }
        out["literal_args"] = _v501;
        var _v506 = JsonValue.array();
        for (var _item506 in this.constrained_aliases) {
            _v506.append(_item506.to_json());
        }
        out["constrained_aliases"] = _v506;
        var _v508 = JsonValue.array();
        for (var _item508 in this.trait_types) {
            _v508.append(_item508.to_json());
        }
        out["trait_types"] = _v508;
        var _v510 = JsonValue.array();
        for (var _item510 in this.conversions) {
            _v510.append(_item510.to_json());
        }
        out["conversions"] = _v510;
        var _v512 = JsonValue.object();
        for (var (_key512, _item512) in this.overload_sets) {
            var _v513 = JsonValue.array();
            for (var _item513 in _item512) {
                _v513.append(JsonValue.String(_item513));
            }
            _v512[_key512] = _v513;
        }
        out["overload_sets"] = _v512;
        var _v515 = JsonValue.object();
        for (var (_key515, _item515) in this.overload_unions) {
            var _v516 = JsonValue.array();
            for (var _item516 in _item515) {
                var _v517 = JsonValue.array();
                for (var _item517 in _item516) {
                    _v517.append(JsonValue.String(_item517));
                }
                _v516.append(_v517);
            }
            _v515[_key515] = _v516;
        }
        out["overload_unions"] = _v515;
        var _v519 = JsonValue.object();
        for (var (_key519, _item519) in this.method_overload_sets) {
            var _v520 = JsonValue.object();
            for (var (_key520, _item520) in _item519) {
                var _v521 = JsonValue.array();
                for (var _item521 in _item520) {
                    _v521.append(JsonValue.String(_item521));
                }
                _v520[_key520] = _v521;
            }
            _v519[_key519] = _v520;
        }
        out["method_overload_sets"] = _v519;
        out["extension_scopes"] = this.extension_scopes.to_json();
        var _v524 = JsonValue.array();
        for (var _item524 in this.private_functions) {
            _v524.append(_item524.to_json());
        }
        out["private_functions"] = _v524;
        var _v526 = JsonValue.array();
        for (var _item526 in this.file_private_functions) {
            _v526.append(_item526.to_json());
        }
        out["file_private_functions"] = _v526;
        var _v528 = JsonValue.array();
        for (var _item528 in this.call_targets) {
            var _v529 = JsonValue.array();
            var _t529 = _item528;
            var (_t529_0, _t529_1) = _t529;
            _v529.append(_t529_0.to_json());
            _v529.append(JsonValue.String(_t529_1));
            _v528.append(_v529);
        }
        out["call_targets"] = _v528;
        var _v532 = JsonValue.array();
        for (var _item532 in this.argument_names) {
            var _v533 = JsonValue.array();
            var _t533 = _item532;
            var (_t533_0, _t533_1) = _t533;
            _v533.append(_t533_0.to_json());
            _v533.append(JsonValue.String(_t533_1));
            _v532.append(_v533);
        }
        out["argument_names"] = _v532;
        var _v536 = JsonValue.array();
        for (var _item536 in this.namespaces) {
            _v536.append(JsonValue.String(_item536));
        }
        out["namespaces"] = _v536;
        var _v538 = JsonValue.array();
        for (var _item538 in this.cached_files) {
            _v538.append(JsonValue.Bool(_item538));
        }
        out["cached_files"] = _v538;
        var _v540 = JsonValue.object();
        for (var (_key540, _item540) in this.recorded_summaries) {
            _v540[_key540.to_json().to_string()] = JsonValue.String(_item540);
        }
        out["recorded_summaries"] = _v540;
        var _v542 = JsonValue.array();
        for (var _item542 in this.stripped) {
            _v542.append(_item542.to_json());
        }
        out["stripped"] = _v542;
        out["templates"] = this.templates.to_json();
        out["checked"] = this.checked.to_json();
        var _v546 = JsonValue.object();
        for (var (_key546, _item546) in this.spec_requests) {
            _v546[_key546] = _item546.to_json();
        }
        out["spec_requests"] = _v546;
        out["record_summaries"] = JsonValue.Bool(this.record_summaries);
        var _v549 = JsonValue.array();
        for (var _item549 in this.summaries_to_record) {
            var _v550 = JsonValue.array();
            var _t550 = _item549;
            var (_t550_0, _t550_1) = _t550;
            _v550.append(_t550_0.to_json());
            _v550.append(JsonValue.String(_t550_1));
            _v549.append(_v550);
        }
        out["summaries_to_record"] = _v549;
        var _v553 = JsonValue.object();
        for (var (_key553, _item553) in this.caller_copies) {
            var _v554 = JsonValue.array();
            for (var _item554 in _item553) {
                _v554.append(JsonValue.Bool(_item554));
            }
            _v553[_key553] = _v554;
        }
        out["caller_copies"] = _v553;
        out["linked"] = JsonValue.Bool(this.linked);
        return out;
    }
}

## `Checked`, a type of the sema model.
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
        var _c564 = HashMap<String, (Loc, String)>();
        for (var (_key564, _item564) in this.summaries) {
            var (_t565_0, _t565_1) = _item564;
            _c564[_key564] = (_t565_0, _t565_1);
        }
        return Checked(
            structs = this.structs.copy(),
            functions = this.functions.copy(),
            globals = this.globals.copy(),
            extensions = this.extensions,
            summaries = _c564
        );
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Checked");
        into.add(this.structs.count);
        for (var _item564 in this.structs) {
            into.add_text(_item564);
        }
        into.add(this.functions.count);
        for (var _item566 in this.functions) {
            into.add_text(_item566);
        }
        into.add(this.globals.count);
        for (var _item568 in this.globals) {
            into.add_text(_item568);
        }
        into.add(this.extensions as ulong);
        into.add(this.summaries.count);
        for (var (_key571, _item571) in this.summaries) {
            into.add_text(_key571);
            var (_t573_0, _t573_1) = _item571;
            _t573_0.fingerprint(into);
            into.add_text(_t573_1);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        var _v557 = JsonValue.array();
        for (var _item557 in this.structs) {
            _v557.append(JsonValue.String(_item557));
        }
        out["structs"] = _v557;
        var _v559 = JsonValue.array();
        for (var _item559 in this.functions) {
            _v559.append(JsonValue.String(_item559));
        }
        out["functions"] = _v559;
        var _v561 = JsonValue.array();
        for (var _item561 in this.globals) {
            _v561.append(JsonValue.String(_item561));
        }
        out["globals"] = _v561;
        out["extensions"] = unsigned_json(this.extensions);
        var _v564 = JsonValue.object();
        for (var (_key564, _item564) in this.summaries) {
            var _v565 = JsonValue.array();
            var _t565 = _item564;
            var (_t565_0, _t565_1) = _t565;
            _v565.append(_t565_0.to_json());
            _v565.append(JsonValue.String(_t565_1));
            _v564[_key564] = _v565;
        }
        out["summaries"] = _v564;
        return out;
    }
}

## `SpecRequest`, a type of the sema model.
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

## `Templates`, a type of the sema model.
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
        var _c571 = Array<StructDef>();
        for (var _item571 in this.structs) {
            _c571.append(_item571.copy());
        }
        var _c573 = Array<FunctionDef>();
        for (var _item573 in this.functions) {
            _c573.append(_item573.copy());
        }
        return Templates(frozen = this.frozen, structs = _c571, functions = _c573);
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("Templates");
        into.add(this.frozen ? 1 : 0);
        into.add(this.structs.count);
        for (var _item579 in this.structs) {
            _item579.fingerprint(into);
        }
        into.add(this.functions.count);
        for (var _item581 in this.functions) {
            _item581.fingerprint(into);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["frozen"] = JsonValue.Bool(this.frozen);
        var _v571 = JsonValue.array();
        for (var _item571 in this.structs) {
            _v571.append(_item571.to_json());
        }
        out["structs"] = _v571;
        var _v573 = JsonValue.array();
        for (var _item573 in this.functions) {
            _v573.append(_item573.to_json());
        }
        out["functions"] = _v573;
        return out;
    }
}

## `TypeFlags`, a type of the sema model.
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

## `TypeName`, a type of the sema model.
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
        var _c576 = Array<TypeName>();
        for (var _item576 in this.sub_types) {
            _c576.append(_item576.copy());
        }
        return TypeName(name = this.name, sub_types = _c576, flags = this.flags, labels = this.labels.copy());
    }

    ## Adds this to `into`: equal values add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add_text("TypeName");
        into.add_text(this.name);
        into.add(this.sub_types.count);
        for (var _item584 in this.sub_types) {
            _item584.fingerprint(into);
        }
        this.flags.fingerprint(into);
        into.add(this.labels.count);
        for (var _item587 in this.labels) {
            into.add_text(_item587);
        }
    }

    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(this.name);
        var _v576 = JsonValue.array();
        for (var _item576 in this.sub_types) {
            _v576.append(_item576.to_json());
        }
        out["sub_types"] = _v576;
        out["flags"] = this.flags.to_json();
        var _v579 = JsonValue.array();
        for (var _item579 in this.labels) {
            _v579.append(JsonValue.String(_item579));
        }
        out["labels"] = _v579;
        return out;
    }
}

## The one key of the object `unsigned_json` makes for a value too large
## for `JsonValue.Integer`; `canonical_json` writes that object as the
## value's digits. A key, not a string prefix: the model's strings hold
## the program's text, but its keys are field names and identifiers.
export const UNSIGNED_MARK = "\u{1}unsigned";

## Returns `value` as JSON: an integer, or for one past `long`'s range (a
## `WithSubject` id), an object holding its digits under `UNSIGNED_MARK`.
##
## @param value the value
## @returns the JSON
export unsigned_json(value: ulong): JsonValue {
    if (value <= 9223372036854775807) {
        return JsonValue.Integer(value as long);
    }
    return _tagged(UNSIGNED_MARK, JsonValue.String($"{value}"));
}

_tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}
