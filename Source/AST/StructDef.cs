using System;
using LLVMSharp.Interop;

namespace Pepper.AST {
    public class StructDef : Symbol {
        public FunctionDef Constructor { get; private set; }
        public FunctionDef Destructor { get; private set; }
        public List<VariableDef> Fields = new();
        public List<MethodDef> Methods = new();

        public StructDef(string name)
            : base(new StructType(name), name) {
            Constructor = new FunctionDef(Mangle.Method(Name, "__ctor"), Type, Enumerable.Empty<FunctionDef.Parameter>());
            Destructor = new FunctionDef(Mangle.Method(Name, "__dtor"), Types.Void, Enumerable.Empty<FunctionDef.Parameter>())
        }
    }
}
