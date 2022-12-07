using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Metadata;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal abstract class Type {
        public string Name = String.Empty;
        public LLVMTypeRef Ref;

        public Type(string name) {
            Name = name;
            Context.Default.Locals.AddType(this);
        }

        public abstract Value New(LLVMBuilderRef builder, string name = "");
        public abstract Value Coerce(Value val);

        internal Type Pointer() {
            return new IntegralType($"{Name}*", LLVMTypeRef.CreatePointer(Ref, 0), 
                (val, type) => throw new NotImplementedException($"Coercion to pointer is not implemented for {Name}"));
        }

        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
    }

    internal class IntegralType : Type {
        public Func<LLVMValueRef, Type, Value> EmitCoerce;

        public IntegralType(string name, LLVMTypeRef typeRef, Func<LLVMValueRef, Type, Value> coerce) : base(name) {
            Ref = typeRef;
            EmitCoerce = coerce;
        }

        public override Value New(LLVMBuilderRef builder, string name) {
            return new Value(this, name, builder);
        }

        public static void StaticInit() {
            Context.Default.Locals.AliasType(I8, "char");
            Context.Default.Locals.AliasType(U8, "byte");
            Context.Default.Locals.AliasType(I32, "int");
            Context.Default.Locals.AliasType(U32, "uint");
            Context.Default.Locals.AliasType(I64, "long");
            Context.Default.Locals.AliasType(U64, "ulong");
            Context.Default.Locals.AliasType(Double, "double");
            Context.Default.Locals.AliasType(Float, "float");
        }

        public override Value Coerce(Value val) {
            return EmitCoerce(val, this);
        }

        public static readonly IntegralType Void = new("void", LLVMTypeRef.Void, (_, _) => throw new Exception("Cannot convert a value to void"));
        public static readonly IntegralType I8 = new("i8", LLVMTypeRef.Int8, (val, type) => {
            return new Value(I8!, LLVMValueRef.CreateConstIntCast(val, type, true));
        });
        public static readonly IntegralType U8 = new("u8", LLVMTypeRef.Int8, (val, type) => {
            return new Value(U8!, LLVMValueRef.CreateConstIntCast(val, type, false));
        });
        public static readonly IntegralType I32 = new("i32", LLVMTypeRef.Int32, (val, type) => {
            return new Value(I32!, LLVMValueRef.CreateConstIntCast(val, type, true));
        });
        public static readonly IntegralType U32 = new("u32", LLVMTypeRef.Int32, (val, type) => {
            return new Value(U32!, LLVMValueRef.CreateConstIntCast(val, type, false));
        });
        public static readonly IntegralType I64 = new("i64", LLVMTypeRef.Int64, (val, type) => {
            return new Value(I64!, LLVMValueRef.CreateConstIntCast(val, type, true));
        });
        public static readonly IntegralType U64 = new("u64", LLVMTypeRef.Int32, (val, type) => {
            return new Value(U64!, LLVMValueRef.CreateConstIntCast(val, type, false));
        });
        public static readonly IntegralType Bool = new("bool", LLVMTypeRef.Int1, (val, type) => {
            return new Value(Bool!, LLVMValueRef.CreateConstIntCast(val, type, false));
        });
        public static readonly IntegralType Double = new("f64", LLVMTypeRef.Double, (val, type) => {
            return new Value(Double!, LLVMValueRef.CreateConstFPCast(val, type));
        });
        public static readonly IntegralType Float = new("f32", LLVMTypeRef.Float, (val, type) => { 
            return new Value(Float!, LLVMValueRef.CreateConstFPCast(val, type)); 
        });
    }

    internal class FunctionType : Type {
        public Type ReturnType = IntegralType.Void;
        public IEnumerable<Value> Parameters { get; private set; }
        public bool Varargs = false;

        private FunctionType(Type returnType, IEnumerable<Value> parameters, bool varargs = false)
            : base(Signature(returnType, parameters, varargs)) {
            Ref = LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray(), varargs);
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;
        }

        public override Value New(LLVMBuilderRef builder, string name = "") {
            throw new NotImplementedException();
        }

        public override Value Coerce(Value val) {
            throw new NotImplementedException();
        }

        public static FunctionType Create(Type returnType, IEnumerable<Value> parameters, bool varargs = false) {
            string sig = Signature(returnType, parameters, varargs);
            var func = Context.Default.Locals.GetType<FunctionType>(sig);
            if (func != null) {
                return func;
            }
            return new FunctionType(returnType, parameters, varargs);
        }

        static string Signature(Type returnType, IEnumerable<Value> parameters, bool varargs = false) {
            var paramsList = string.Join(", ", parameters.Select(p => $"{p.Type.Name} {p.Name}"));
            var ellipsis = varargs ? ", ..." : "";
            return $"{returnType.Name}({paramsList}{ellipsis})";
        }
    }
}


