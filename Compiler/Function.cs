using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Function {
        public LLVMTypeRef TypeRef;
        public LLVMValueRef Ref;
        public string Name { get; set; } = String.Empty;
        public string ReturnType { get; set; } = "void";
        public IEnumerable<Variable> Parameters { get; set; } = new List<Variable>();
    }
}
