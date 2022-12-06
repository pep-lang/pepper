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

        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
    }

    internal class IntegralType : Type {
        public IntegralType(string name, LLVMTypeRef typeRef) : base(name) {
            Ref = typeRef;
        }

        public override LLVMValueRef New(LLVMBuilderRef builder, string name) {
            return builder.BuildAlloca(Ref, name);
        }

        public static void StaticInit() {
            // Force static initialization
            var dummy = Void;
        }

        public static readonly IntegralType Void = new("void", LLVMTypeRef.Void);
        public static readonly IntegralType I32 = new("i32", LLVMTypeRef.Int32);
        public static readonly IntegralType U32 = new("u32", LLVMTypeRef.Int32);
        public static readonly IntegralType I64 = new("i64", LLVMTypeRef.Int64);
        public static readonly IntegralType U64 = new("u64", LLVMTypeRef.Int32);
        public static readonly IntegralType Bool = new("bool", LLVMTypeRef.Int1);
        public static readonly IntegralType Double = new("f64", LLVMTypeRef.Double);
        public static readonly IntegralType Float = new("f32", LLVMTypeRef.Float);
    }
}
