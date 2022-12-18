using LLVMSharp.Interop;
using System;
namespace Pepper {
    public class StructType : Type {
        static LLVMTypeRef StructTypeInfo = LLVMTypeRef.CreateStruct(
            new LLVMTypeRef[]{
                LLVMTypeRef.Int32, // typeid (TODO: replace with pointer to type info as id)
                LLVMTypeRef.CreatePointer(LLVMTypeRef.Int8, 0), // name
            }, true);

        static LLVMTypeRef[] StructVtable = {
            LLVMTypeRef.CreatePointer(StructTypeInfo, 0),
        };

        public StructType(string name)
            : base(name, LLVMTypeRef.CreateStruct(StructVtable, false)) {
        }

        public StructType(string name, LLVMTypeRef type)
            : base(name, type) {

        }
    }
}
