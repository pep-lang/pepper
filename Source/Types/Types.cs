using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public static class Types {
        public static void StaticInit() {
            Runtime.Environment.AliasType(Int8, "char");
            Runtime.Environment.AliasType(UInt8, "byte");
            Runtime.Environment.AliasType(Int32, "int");
            Runtime.Environment.AliasType(UInt32, "uint");
            Runtime.Environment.AliasType(Int64, "long");
            Runtime.Environment.AliasType(UInt64, "ulong");

            Runtime.Environment.AliasType(Double, "double");
            Runtime.Environment.AliasType(Float, "float");
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

        public static readonly BoolType Bool = new();

        public static readonly FloatType Double = new("f64", LLVMTypeRef.Double);
        public static readonly PointerType DoublePtr = Double.Pointer();

        public static readonly FloatType Float = new("f32", LLVMTypeRef.Float);
        public static readonly PointerType FloatPtr = Float.Pointer();

        public static readonly ConstantType<IntegerType, long, ConstantInt> ConstantInt = new(Int64, v => new ConstantInt(v, $"cint.{v}"));
        public static readonly ConstantType<FloatType, double, ConstantFloat> ConstantFloat = new(Double, f => new ConstantFloat(f, $"cfloat.{f}"));
        public static readonly ConstantType<BoolType, bool, ConstantBool> ConstantBool = new(Bool, b => new ConstantBool(b, $"cbool.{b}"));
        public static readonly ConstantType<PointerType, string, ConstantString> ConstantString = new(Int8Ptr, s => new ConstantString(s, "cstr"));
        public static readonly ConstantType<PointerType, IntPtr, ConstantPointer> ConstantPointer = new(Int8Ptr, p => new ConstantPointer(p, "cptr"));

        public static readonly InstructionType Instruction = new("instruction");
    }

}
