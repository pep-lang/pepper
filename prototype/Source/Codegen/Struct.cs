
using CommandLine;
using LLVMSharp.Interop;
using System;
using System.Runtime.CompilerServices;
using System.Xml.Linq;

namespace Pepper.Codegen {
    // A struct's value is its TypeInfo*
    // TODO: should Struct just be the constructor function?
    public class Struct : Value {
        public ObjectType StructType { get; private set; }
        public LLVMValueRef Size => StructType.Ref.SizeOf;
        public FreeFunction Initializer => Methods["__init"];
        public FreeFunction Constructor => Methods["__ctor"];
        public FreeFunction Destructor => Methods["__dtor"];
        public OrderedMap<string, Symbol> Fields => StructType.Fields;
        public OrderedMap<string, FreeFunction> Methods => StructType.Methods.Select(m => new KeyValuePair<string, FreeFunction>(m.Key, (FreeFunction)m.Value)).ToOrderedMap();

        public Struct(ObjectType type, string name)
            : base(type.Pointer(), PointerType.Null, name) {
            StructType = type;
            // update the value to point to the type info for this struct
            //Replace(TypeInfo);
        }

        public override string ToString() {
            return Name;
        }
    }
}
