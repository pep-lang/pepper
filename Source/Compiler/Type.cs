using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Metadata;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    using CoerceFunc = Func<LLVMValueRef, Type, Value>;

    internal abstract class Type {
        public readonly string Name;
        public LLVMTypeRef Ref { get; protected set; }
        public bool IsInt { get; protected set; } = false;
        public bool IsReal { get; protected set; } = false;
        public bool IsPointer { get; protected set; } = false;

        public Type(string name, LLVMTypeRef typeRef) {
            Name = name;
            Ref = typeRef;
            Context.Default.Locals.AddType(this);
        }

        public abstract Value Coerce(Value val);
        public abstract PointerType Pointer();

        internal LLVMValueRef Alloc(LLVMBuilderRef? builder, string name = "") {
            builder ??= Context.Default.Locals.FunctionRegisters;
            return builder.Value.BuildAlloca(this, name);
        }

        public override bool Equals(object? other) => (other is Type rhs) && Ref == rhs.Ref;

        public override int GetHashCode() => Ref.GetHashCode();

        public override string ToString() => Name;
        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
    }

    internal abstract class NativeType : Type {
        public NativeType(string name, LLVMTypeRef typeRef) 
            : base(name, typeRef) {            
        }

        public override PointerType Pointer() {
            return new PointerType($"{Name}*", LLVMTypeRef.CreatePointer(this, 0));
        }

        public static void StaticInit() {
            VoidType.StaticInit();
            IntegerType.StaticInit();
            FloatType.StaticInit();
        }
    }

    internal class PointerType : Type {
        public PointerType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsPointer = true;
        }

        public override PointerType Pointer() {
            throw new CompileException($"Pointer to {this} is disallowed");
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this)) {
                return val;
            }

            var type = val.Type;
            if (type.IsPointer) {
                return new Value(this, LLVMValueRef.CreateConstPointerCast(val, this));
            }
            throw new CompileException($"Cannot convert non-pointer type {type} to {this}");
        }
    }

    internal class VoidType : NativeType {
        public VoidType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
        }

        public override PointerType Pointer() {
            return new PointerType("void*", this);
        }

        public override Value Coerce(Value val) {
            throw new CompileException($"Cannot convert {val.Type} to void");
        }

        public static new void StaticInit() {

        }

        public static readonly VoidType Void = new("void", LLVMTypeRef.Void);
        public static readonly PointerType VoidPtr = Void.Pointer();
    }

    internal class IntegerType : NativeType {
        public readonly bool Signed = true;
        public uint Width => Ref.IntWidth;

        public IntegerType(string name, LLVMTypeRef typeRef, bool signed = true)
            : base(name, typeRef) {
            Signed = signed;
            IsInt = true;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }
            return new Value(this, LLVMValueRef.CreateConstIntCast(val, this, Signed));
        }

        public static new void StaticInit() {
            Context.Default.Locals.AliasType(Int8, "char");
            Context.Default.Locals.AliasType(UInt8, "byte");
            Context.Default.Locals.AliasType(Int32, "int");
            Context.Default.Locals.AliasType(UInt32, "uint");
            Context.Default.Locals.AliasType(Int64, "long");
            Context.Default.Locals.AliasType(UInt64, "ulong");
        }

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
    }

    internal class FloatType : NativeType {
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
                return new Value(Double!, LLVMValueRef.CreateConstSIToFP(val, type));
            } else {
                return new Value(Double!, LLVMValueRef.CreateConstFPExt(val, type));
            }
        }

        public static new void StaticInit() {
            Context.Default.Locals.AliasType(Double, "double");
            Context.Default.Locals.AliasType(Float, "float");
        }

        public static readonly FloatType Double = new("f64", LLVMTypeRef.Double);
        public static readonly PointerType DoublePtr = Double.Pointer();

        public static readonly FloatType Float = new("f32", LLVMTypeRef.Float);
        public static readonly PointerType FloatPtr = Float.Pointer();
    }

    //internal class UserType : Type {
    //    public UserType(string name, LLVMTypeRef typeRef, Func<LLVMValueRef, Type, Value> coerce) : base(name) {

    //    }
    //}

    internal class FunctionType : Type {
        public Type ReturnType { get; private set; }
        public IEnumerable<TypedValue> Parameters { get; private set; }
        public bool Varargs { get; private set; } = false;

        private FunctionType(Type returnType, IEnumerable<TypedValue> parameters, bool varargs = false)
            : base(Signature(returnType, parameters, varargs), LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray(), varargs)) {
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;
        }

        public override PointerType Pointer() => throw new NotImplementedException();

        public override Value Coerce(Value val) {
            throw new NotImplementedException();
        }

        public static FunctionType Create(Type returnType, IEnumerable<TypedValue> parameters, bool varargs = false) {
            string sig = Signature(returnType, parameters, varargs);
            var func = Context.Default.Locals.GetType<FunctionType>(sig);
            if (func != null) {
                return func;
            }
            return new FunctionType(returnType, parameters, varargs);
        }

        static string Signature(Type returnType, IEnumerable<TypedValue> parameters, bool varargs = false) {
            var paramsList = string.Join(", ", parameters.Select(p => $"{p.Type.Name} {p.Name}"));
            var ellipsis = varargs ? ", ..." : "";
            return $"{returnType.Name}({paramsList}{ellipsis})";
        }
    }
}


