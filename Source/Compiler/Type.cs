using LLVMSharp;
using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Data;
using System.Xml.Linq;

namespace Pepper {
    public abstract class Type {
        public readonly string Name;
        public LLVMTypeRef Ref { get; protected set; }
        public bool IsInt { get; protected set; } = false;
        public bool IsReal { get; protected set; } = false;
        public bool IsPointer { get; protected set; } = false;

        public Type(string name, LLVMTypeRef typeRef) {
            Name = name;
            Ref = typeRef;
            Context.Runtime.AddType(this);
        }

        public abstract Value Coerce(Value val);
        public abstract PointerType Pointer();

        public LLVMValueRef Alloc(LLVMBuilderRef? builder, string name = "") {
            builder ??= Context.Default.Locals.FunctionRegisters;
            return builder.Value.BuildAlloca(this, name);
        }

        public virtual uint Bits => 0;
        public virtual Value DefaultValue => throw new InternalCompilerException($"Type {Name} does not have a default value");
        public virtual Value Add(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Sub(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Mul(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Div(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Mod(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Less(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Greater(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value LessEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value GreaterEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value LShift(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value RShift(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Equal(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value NotEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Assign(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitAnd(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitOr(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitXor(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value AsBool(Value val) => throw new NotImplementedException();

        public override bool Equals(object? other) => (other is Type rhs) && Ref == rhs.Ref;

        public override int GetHashCode() => Ref.GetHashCode();

        public override string ToString() => Name;
        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
    }

    public abstract class NativeType : Type {
        protected static LLVMBuilderRef Builder {
            get {
                return Context.Default.Locals.Builder;
            }
        }

        public override uint Bits => Ref.IntWidth;

        public NativeType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
        }

        public override PointerType Pointer() {
            return new PointerType($"{Name}*", LLVMTypeRef.CreatePointer(this, 0));
        }

        public abstract Value CreateConstant<U>(U value);
    }

    public abstract class DerivedFrom<T> : NativeType where T : NativeType {
        readonly T Base;

        public DerivedFrom(T baseType)
            : base(baseType.Name, baseType) {
            Base = baseType;
        }

        public override Value DefaultValue => Base.DefaultValue;
        public override Value Coerce(Value val) => Base.Coerce(val);
        public override PointerType Pointer() => Base.Pointer();
        public override Value Add(Value lhs, Value rhs) => Base.Add(lhs, rhs);
        public override Value Sub(Value lhs, Value rhs) => Base.Sub(lhs, rhs);
        public override Value Mul(Value lhs, Value rhs) => Base.Mul(lhs, rhs);
        public override Value Div(Value lhs, Value rhs) => Base.Div(lhs, rhs);
        public override Value Mod(Value lhs, Value rhs) => Base.Mod(lhs, rhs);
        public override Value Pow(Value lhs, Value rhs) => Base.Pow(lhs, rhs);
        public override Value Less(Value lhs, Value rhs) => Base.Less(lhs, rhs);
        public override Value Greater(Value lhs, Value rhs) => Base.Greater(lhs, rhs);
        public override Value LessEqual(Value lhs, Value rhs) => Base.LessEqual(lhs, rhs);
        public override Value GreaterEqual(Value lhs, Value rhs) => Base.GreaterEqual(lhs, rhs);
        public override Value LShift(Value lhs, Value rhs) => Base.LShift(lhs, rhs);
        public override Value RShift(Value lhs, Value rhs) => Base.RShift(lhs, rhs);
        public override Value Equal(Value lhs, Value rhs) => Base.Equal(lhs, rhs);
        public override Value NotEqual(Value lhs, Value rhs) => Base.NotEqual(lhs, rhs);
        public override Value Assign(Value lhs, Value rhs) => Base.Assign(lhs, rhs);
        public override Value BitAnd(Value lhs, Value rhs) => Base.BitAnd(lhs, rhs);
        public override Value BitOr(Value lhs, Value rhs) => Base.BitOr(lhs, rhs);
        public override Value BitXor(Value lhs, Value rhs) => Base.BitXor(lhs, rhs);
        public override Value AsBool(Value val) => Base.AsBool(val);
    }

    public class PointerType : NativeType {
        public override Value DefaultValue => new(Types.VoidPtr, LLVMValueRef.CreateConstPointerNull(Types.VoidPtr), "nullptr");
        public PointerType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsPointer = true;
        }

        public override PointerType Pointer() {
            throw new CompileException($"Pointer to {this} is disallowed");
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }

            var type = val.Type;
            if (type.IsPointer) {
                return new Value(this, LLVMValueRef.CreateConstPointerCast(val, this));
            }
            throw new CompileException($"Cannot convert non-pointer type {type} to {this}");
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantPointer((IntPtr)Convert.ChangeType(value, typeof(IntPtr))!);
        }

        public override Value Equal(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntEQ, lhs, rhs));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(rhs); return lhs; }
    }

    public class VoidType : NativeType {
        public override Value DefaultValue => throw new InternalCompilerException("void should never be used as a default value");

        public VoidType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
        }

        public override PointerType Pointer() {
            return new PointerType("void*", this);
        }

        public override Value Coerce(Value val) {
            throw new CompileException($"Cannot convert {val.Type} to void");
        }

        public override Value CreateConstant<U>(U value) => throw new InternalCompilerException("It is not possible to create a void constant");
    }

    public class IntegerType : NativeType {
        public readonly bool Signed = true;

        public IntegerType(string name, LLVMTypeRef typeRef, bool signed = true)
            : base(name, typeRef) {
            Signed = signed;
            IsInt = true;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }
            bool signed = val.Type != Types.Bool && Signed;
            if (val.Type.IsInt) {
                if (this.Bits > val.Type.Bits)
                    return new Value(this, Builder.BuildZExtOrBitCast(val.Load(), this)).Store();
                else
                    return new Value(this, Builder.BuildTruncOrBitCast(val.Load(), this)).Store();
            }
            Func<LLVMValueRef, LLVMTypeRef, string, LLVMValueRef> convert = signed ? Builder.BuildFPToSI : Builder.BuildFPToUI;
            return new Value(this, convert(val.Load(), this, "")).Store();
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantInt((long)Convert.ChangeType(value, typeof(long))!);
        }

        public override Value DefaultValue => new(this, LLVMValueRef.CreateConstInt(this, 0, Signed), $"{Name}.zero");
        public override Value Add(Value lhs, Value rhs) => new(this, Builder.BuildAdd(lhs.Load(), rhs.Load(), "add"));
        public override Value Sub(Value lhs, Value rhs) => new(this, Builder.BuildSub(lhs.Load(), rhs.Load(), "sub"));
        public override Value Mul(Value lhs, Value rhs) => new(this, Builder.BuildMul(lhs.Load(), rhs.Load(), "mul"));
        public override Value Div(Value lhs, Value rhs) => new(this, Builder.BuildSDiv(lhs.Load(), rhs.Load(), "div"));
        public override Value Mod(Value lhs, Value rhs) => new(this, Builder.BuildSRem(lhs.Load(), rhs.Load(), "mod"));
        public override Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public override Value Less(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildICmp(LLVMIntPredicate.LLVMIntULT, lhs.Load(), rhs.Load(), "lt"));
        public override Value Greater(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildICmp(LLVMIntPredicate.LLVMIntUGT, lhs.Load(), rhs.Load(), "gt"));
        public override Value LessEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntSLE, lhs.Load(), rhs.Load(), "le"));
        public override Value GreaterEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntSGE, lhs.Load(), rhs.Load(), "ge"));
        public override Value LShift(Value lhs, Value rhs) => new(this, Builder.BuildShl(lhs.Load(), rhs.Load(), "lshift"));
        public override Value RShift(Value lhs, Value rhs) => new(this, Builder.BuildAShr(lhs.Load(), rhs.Load(), "rshift"));
        public override Value Equal(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntEQ, lhs.Load(), rhs.Load(), "eq"));
        public override Value NotEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntNE, lhs.Load(), rhs.Load(), "ne"));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(rhs); return lhs; }
        public override Value BitAnd(Value lhs, Value rhs) => new(this, Builder.BuildAnd(lhs.Load(), rhs.Load(), "and"));
        public override Value BitOr(Value lhs, Value rhs) => new(this, Builder.BuildOr(lhs.Load(), rhs.Load(), "or"));
        public override Value BitXor(Value lhs, Value rhs) => new(this, Builder.BuildXor(lhs.Load(), rhs.Load(), "xor"));
        public override Value AsBool(Value val) {
            var name = val.Name != "" ? $"{val.Name}.bool" : $"{val.ToString()[val.ToString().IndexOf(" ")..].Replace("%", null)}";
            return new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntNE, val.Load(), ConstantBool.False.As(this), name));
        }
    }

    public class ConstantType<T, V, C> : DerivedFrom<T>
        where T : NativeType
        where C : Constant {
        readonly Func<V, C> Create;

        public ConstantType(T baseType, Func<V, C> create)
            : base(baseType) {
            Create = create;
        }

        public override Value DefaultValue => base.DefaultValue;

        public override Value CreateConstant<U>(U value) {
            return Create((V)Convert.ChangeType(value, typeof(V))!);
        }
    }

    public class FloatType : NativeType {
        public FloatType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsReal = true;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }

            var type = val.Type;
            if (type.IsInt) {
                var intType = (type as IntegerType)!;
                if (intType.Signed)
                    return new Value(this, Builder.BuildSIToFP(val.Load(), this)).Store();
                else
                    return new Value(this, Builder.BuildUIToFP(val.Load(), this)).Store();
            } else {
                if (Bits > val.Type.Bits)
                    return new Value(this, Builder.BuildFPExt(val.Load(), this)).Store();
                else
                    return new Value(this, Builder.BuildFPTrunc(val.Load(), this)).Store();
            }
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantFloat((double)Convert.ChangeType(value, typeof(double))!);
        }

        public override uint Bits => Ref == LLVMTypeRef.Float ? 32u : 64u;
        public override Value DefaultValue => new ConstantFloat(0, $"{Name}.zero");
        public override Value Add(Value lhs, Value rhs) => new(this, Builder.BuildFAdd(lhs.Load(), rhs.Load(), "add"));
        public override Value Sub(Value lhs, Value rhs) => new(this, Builder.BuildFSub(lhs.Load(), rhs.Load(), "sub"));
        public override Value Mul(Value lhs, Value rhs) => new(this, Builder.BuildFMul(lhs.Load(), rhs.Load(), "mul"));
        public override Value Div(Value lhs, Value rhs) => new(this, Builder.BuildFDiv(lhs.Load(), rhs.Load(), "div"));
        public override Value Mod(Value lhs, Value rhs) => new(this, Builder.BuildFRem(lhs.Load(), rhs.Load(), "mod"));
        public override Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public override Value Less(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealULT, lhs.Load(), rhs.Load(), "lt"));
        public override Value Greater(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUGT, lhs.Load(), rhs.Load(), "gt"));
        public override Value LessEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealULE, lhs.Load(), rhs.Load(), "le"));
        public override Value GreaterEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUGE, lhs.Load(), rhs.Load(), "ge"));
        public override Value Equal(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUEQ, lhs.Load(), rhs.Load(), "eq"));
        public override Value NotEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUNE, lhs.Load(), rhs.Load(), "ne"));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(rhs); return lhs; }
    }

    public static class Types {
        public static void StaticInit() {
            Context.Runtime.AliasType(Int8, "char");
            Context.Runtime.AliasType(UInt8, "byte");
            Context.Runtime.AliasType(Int32, "int");
            Context.Runtime.AliasType(UInt32, "uint");
            Context.Runtime.AliasType(Int64, "long");
            Context.Runtime.AliasType(UInt64, "ulong");

            Context.Runtime.AliasType(Double, "double");
            Context.Runtime.AliasType(Float, "float");
        }

        public static readonly VoidType Void = new("void", LLVMTypeRef.Void);
        public static readonly PointerType VoidPtr = Void.Pointer();

        public static readonly IntegerType Int8 = new("i8", LLVMTypeRef.Int8, true);
        public static readonly PointerType Int8Ptr = Int8.Pointer();

        public static readonly IntegerType UInt8 = new("u8", LLVMTypeRef.Int8, false);
        public static readonly PointerType UInt8Ptr = UInt8.Pointer();

        public static readonly IntegerType Int32 = new("i32", LLVMTypeRef.Int32, true);
        public static readonly PointerType Int32Ptr = Int32.Pointer();

        public static readonly IntegerType UInt32 = new("u32", LLVMTypeRef.Int32, false);
        public static readonly PointerType UInt32Ptr = UInt32.Pointer();

        public static readonly IntegerType Int64 = new("i64", LLVMTypeRef.Int64, true);
        public static readonly PointerType Int64Ptr = Int64.Pointer();

        public static readonly IntegerType UInt64 = new("u64", LLVMTypeRef.Int64, false);
        public static readonly PointerType UInt64Ptr = UInt64.Pointer();

        public static readonly IntegerType Bool = new("bool", LLVMTypeRef.Int1, false);

        public static readonly FloatType Double = new("f64", LLVMTypeRef.Double);
        public static readonly PointerType DoublePtr = Double.Pointer();

        public static readonly FloatType Float = new("f32", LLVMTypeRef.Float);
        public static readonly PointerType FloatPtr = Float.Pointer();

        public static readonly ConstantType<IntegerType, long, ConstantInt> ConstantInt = new(Int64, v => new ConstantInt(v));
        public static readonly ConstantType<FloatType, double, ConstantFloat> ConstantFloat = new(Double, f => new ConstantFloat(f));
        public static readonly ConstantType<IntegerType, bool, ConstantBool> ConstantBool = new(Bool, b => new ConstantBool(b));
        public static readonly ConstantType<PointerType, string, ConstantString> ConstantString = new(Int8Ptr, s => new ConstantString(s));
        public static readonly ConstantType<PointerType, IntPtr, ConstantPointer> ConstantPointer = new(Int8Ptr, p => new ConstantPointer(p));
    }

    //public class UserType : Type {
    //    public UserType(string name, LLVMTypeRef typeRef, Func<LLVMValueRef, Type, Value> coerce) : base(name) {

    //    }
    //}

    public class FunctionType : Type {
        public Type ReturnType { get; private set; }
        public IEnumerable<Symbol> Parameters { get; private set; }
        public bool Varargs { get; private set; } = false;

        private FunctionType(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(Signature(returnType, parameters, varargs), LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray(), varargs)) {
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;
        }

        public override PointerType Pointer() => throw new NotImplementedException();

        public override Value Coerce(Value val) {
            throw new NotImplementedException();
        }

        public static FunctionType Create(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) {
            string sig = Signature(returnType, parameters, varargs);
            try {
                var func = Context.Default.Locals.GetType<FunctionType>(sig);
                if (func != null)
                    return func;
            } catch {
                var func = Context.Runtime.GetType<FunctionType>(sig);
                if (func != null)
                    return func;
            }

            return new FunctionType(returnType, parameters, varargs);
        }

        static string Signature(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) {
            var paramsList = string.Join(", ", parameters.Select(p => $"{p.Type.Name} {p.Name}"));
            var ellipsis = varargs ? ", ..." : "";
            return $"{returnType.Name}({paramsList}{ellipsis})";
        }
    }
}


