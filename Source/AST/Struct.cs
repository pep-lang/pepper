using System;
using LLVMSharp.Interop;

namespace Pepper.AST {
    public class StructDef : Symbol {
        public List<VariableDef> Fields = new();
        public List<MethodDef> Methods = new();

        public StructDef(string name)
            : base(new StructType(name), name) {
        }
    }
}
