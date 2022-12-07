using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
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

        public abstract LLVMValueRef New(LLVMBuilderRef builder, string name = "");
        public abstract LLVMValueRef Coerce(LLVMValueRef val);

        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
    }

    internal class IntegralType : Type {
        public Func<LLVMValueRef, Type, LLVMValueRef> EmitCoerce;

        public IntegralType(string name, LLVMTypeRef typeRef, Func<LLVMValueRef, Type, LLVMValueRef> coerce) : base(name) {
            Ref = typeRef;
            EmitCoerce = coerce;
        }

        public override LLVMValueRef New(LLVMBuilderRef builder, string name) {
            return builder.BuildAlloca(Ref, name);
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

        public override LLVMValueRef Coerce(LLVMValueRef val) {
            return EmitCoerce(val, this);
        }

        public static readonly IntegralType Void = new("void", LLVMTypeRef.Void, (_, _) => throw new Exception("Cannot convert a value to void"));
        public static readonly IntegralType I8 = new("i8", LLVMTypeRef.Int8, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, true);
        });
        public static readonly IntegralType U8 = new("u8", LLVMTypeRef.Int8, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, false);
        });
        public static readonly IntegralType I32 = new("i32", LLVMTypeRef.Int32, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, true);
        });
        public static readonly IntegralType U32 = new("u32", LLVMTypeRef.Int32, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, false);
        });
        public static readonly IntegralType I64 = new("i64", LLVMTypeRef.Int64, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, true);
        });
        public static readonly IntegralType U64 = new("u64", LLVMTypeRef.Int32, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, false);
        });
        public static readonly IntegralType Bool = new("bool", LLVMTypeRef.Int1, (val, type) => {
            return LLVMValueRef.CreateConstIntCast(val, type, false);
        });
        public static readonly IntegralType Double = new("f64", LLVMTypeRef.Double, (val, type) => {
            return LLVMValueRef.CreateConstFPCast(val, type);
        });
        public static readonly IntegralType Float = new("f32", LLVMTypeRef.Float, (val, type) => { 
            return LLVMValueRef.CreateConstFPCast(val, type); 
        });
    }
}
