using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Variable {
        public string Name;
        public Type Type;
        LLVMValueRef Ref;

        public Variable(string name, Type type, LLVMBuilderRef builder) {
            Name = name;
            Type = type;
            Ref = builder.BuildAlloca(type, name);

            Context.Default.Locals.AddVariable(this);
        }

        public static implicit operator LLVMValueRef(Variable v) => v.Ref;
    }
}
