using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public static class LLVMExtensions {
        public static string RegisterName(this LLVMValueRef val) {
            var name = val.ToString();
            if (name.StartsWith("%"))
                return name[1..name.IndexOf(" ")];
            if (name.StartsWith("const"))
                return name[0..name.IndexOf(" ", "const ".Length + 1)].Replace(" ", "_");
            return name;
        }
    }
}
