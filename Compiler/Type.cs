using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Metadata;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    using CoerceFunc = Func<LLVMValueRef, Type, Value>;

    internal abstract class Type {
        public string Name;
        public LLVMTypeRef Ref;

        public Type(string name) {
            System.Diagnostics.Debug.Assert(!name.EndsWith("**"));
            Name = name;
            Context.Default.Locals.AddType(this);
        }

        public abstract Value Coerce(Value val);

        internal abstract Type Pointer();

        internal T Pointer<T>() where T: Type {
            return (T)Pointer();
        }

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
        public CoerceFunc EmitCoerce;

        public NativeType(string name, LLVMTypeRef typeRef, CoerceFunc coerce) : base(name) {
            Ref = typeRef;
            EmitCoerce = coerce;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }
            return EmitCoerce(val, this);
        }
    }

    internal class IntegralType : NativeType {

        public IntegralType(string name, LLVMTypeRef typeRef, CoerceFunc coerce) : base(name, typeRef, coerce) { }

        internal override Type Pointer() {
            return Pointer((val, type) => {
                var ptrType = Context.Default.Locals.GetType($"{Name}*")!;
                return new Value(ptrType, LLVMValueRef.CreateConstPointerCast(val, this), val.Name);
            });
        }

        private Type Pointer(CoerceFunc coerce) {
            return new IntegralType($"{Name}*", LLVMTypeRef.CreatePointer(this, 0), coerce);
        }

        private T Pointer<T>(CoerceFunc coerce) where T : Type {
            return (T)Pointer(coerce);
        }

        public static void StaticInit() {
            Context.Default.Locals.AliasType(Int8, "char");
            Context.Default.Locals.AliasType(UInt8, "byte");
            Context.Default.Locals.AliasType(Int32, "int");
            Context.Default.Locals.AliasType(UInt32, "uint");
            Context.Default.Locals.AliasType(Int64, "long");
            Context.Default.Locals.AliasType(UInt64, "ulong");
            Context.Default.Locals.AliasType(Double, "double");
            Context.Default.Locals.AliasType(Float, "float");
        }

        public static readonly IntegralType Void = new("void", LLVMTypeRef.Void, (_, _) => throw new Exception("Cannot convert a value to void"));
        public static readonly IntegralType VoidPtr = Void.Pointer<IntegralType>((val, type) => {
            return new Value(VoidPtr!, LLVMValueRef.CreateConstPointerCast(val, VoidPtr!));
        });

        public static readonly IntegralType Int8 = new("i8", LLVMTypeRef.Int8, (val, type) => {
            return new Value(Int8!, LLVMValueRef.CreateConstIntCast(val, Int8!, true));
        });
        public static readonly IntegralType Int8Ptr = Int8.Pointer<IntegralType>((val, type) => {
            return new Value(Int8Ptr!, LLVMValueRef.CreateConstPointerCast(val, Int8Ptr!));
        });

        public static readonly IntegralType UInt8 = new("u8", LLVMTypeRef.Int8, (val, type) => {
            return new Value(UInt8!, LLVMValueRef.CreateConstIntCast(val, UInt8!, false));
        });
        public static readonly IntegralType UInt8Ptr = UInt8.Pointer<IntegralType>((val, type) => {
            return new Value(UInt8Ptr!, LLVMValueRef.CreateConstPointerCast(val, UInt8Ptr!));
        });
        
        public static readonly IntegralType Int32 = new("i32", LLVMTypeRef.Int32, (val, type) => {
            return new Value(Int32!, LLVMValueRef.CreateConstIntCast(val, Int32!, true));
        });
        public static readonly IntegralType Int32Ptr = Int32.Pointer<IntegralType>((val, type) => {
            return new Value(Int32Ptr!, LLVMValueRef.CreateConstPointerCast(val, Int32Ptr!));
        });

        public static readonly IntegralType UInt32 = new("u32", LLVMTypeRef.Int32, (val, type) => {
            return new Value(UInt32!, LLVMValueRef.CreateConstIntCast(val, UInt32!, false));
        });
        public static readonly IntegralType UInt32Ptr = UInt32.Pointer<IntegralType>((val, type) => {
            return new Value(UInt32Ptr!, LLVMValueRef.CreateConstPointerCast(val, UInt32Ptr!));
        });

        public static readonly IntegralType Int64 = new("i64", LLVMTypeRef.Int64, (val, type) => {
            return new Value(Int64!, LLVMValueRef.CreateConstIntCast(val, Int64!, true));
        });
        public static readonly IntegralType Int64Ptr = Int64.Pointer<IntegralType>((val, type) => {
            return new Value(Int64Ptr!, LLVMValueRef.CreateConstPointerCast(val, Int64Ptr!));
        });

        public static readonly IntegralType UInt64 = new("u64", LLVMTypeRef.Int64, (val, type) => {
            return new Value(UInt64!, LLVMValueRef.CreateConstIntCast(val, UInt64!, false));
        });
        public static readonly IntegralType UInt64Ptr = UInt64.Pointer<IntegralType>((val, type) => {
            return new Value(UInt64Ptr!, LLVMValueRef.CreateConstPointerCast(val, UInt64Ptr!));
        });

        public static readonly IntegralType Bool = new("bool", LLVMTypeRef.Int1, (val, type) => {
            return new Value(Bool!, LLVMValueRef.CreateConstIntCast(val, type, false));
        });

        public static readonly IntegralType Double = new("f64", LLVMTypeRef.Double, (val, type) => {
            return new Value(Double!, LLVMValueRef.CreateConstFPCast(val, type));
        });
        public static readonly IntegralType DoublePtr = Double.Pointer<IntegralType>();

        public static readonly IntegralType Float = new("f32", LLVMTypeRef.Float, (val, type) => { 
            return new Value(Float!, LLVMValueRef.CreateConstFPCast(val, type)); 
        });
        public static readonly IntegralType FloatPtr = Float.Pointer<IntegralType>();
    }

    //internal class UserType : Type {
    //    public UserType(string name, LLVMTypeRef typeRef, Func<LLVMValueRef, Type, Value> coerce) : base(name) {

    //    }
    //}

    internal class FunctionType : Type {
        public Type ReturnType = IntegralType.Void;
        public IEnumerable<TypedValue> Parameters { get; private set; }
        public bool Varargs = false;

        private FunctionType(Type returnType, IEnumerable<TypedValue> parameters, bool varargs = false)
            : base(Signature(returnType, parameters, varargs)) {
            Ref = LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray(), varargs);
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;
        }

        internal override Type Pointer() => throw new NotImplementedException();

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


