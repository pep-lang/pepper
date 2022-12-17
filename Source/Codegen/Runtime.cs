using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Codegen {
    // Runtime receives all static initialization of global functions and types, it is
    // never torn down or re-initialized. It it assumed that it will not change after
    // initialization
    public class Runtime : Scope {

        static Runtime() {
            Types.StaticInit();
            ExternFunction.StaticInit();
        }

        public static Runtime Environment { get; private set; } = new();
    }
}
