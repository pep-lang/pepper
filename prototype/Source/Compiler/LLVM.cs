using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public static class LLVMExtensions {
        public static string RegisterName(this LLVMValueRef val, string hint = "") {
            var name = val.ToString().Trim();
            if (name.StartsWith("%"))
                return name[1..name.IndexOf(" ")];
            if (hint.StartsWith("const"))
                return hint[0..hint.IndexOf(" ", "const ".Length + 1)].Replace(" ", "_");
            return name;
        }
    }
}
