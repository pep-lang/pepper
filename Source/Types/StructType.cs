using LLVMSharp.Interop;
using Pepper.AST;
using System;
namespace Pepper {
    public class StructType : Type {
        // This is placeholder, a new one will be created once the structure is known
        static readonly StructType StructVTable = new("VTable", LLVMTypeRef.CreateStruct(Array.Empty<LLVMTypeRef>(), true));

        static readonly StructType StructTypeInfo = new("TypeInfo", LLVMTypeRef.CreateStruct(
            new LLVMTypeRef[]{
                StructVTable,
                Types.Int32, // ref count
                LLVMTypeRef.CreatePointer(LLVMTypeRef.Int8, 0), // name
            }, true));

        public StructType(string name)
            : base(name, StructTypeInfo) {
        }

        public StructType(string name, LLVMTypeRef type)
            : base(name, type) {

        }
    }
}
