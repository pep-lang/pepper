using LLVMSharp;
using LLVMSharp.Interop;
using Pepper.AST;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public unsafe class JIT {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate Int32 IntMain0();

        static JIT() {
            //LLVM.LinkInMCJIT();
            LLVM.InitializeX86TargetMC();
            LLVM.InitializeX86Target();
            LLVM.InitializeX86TargetInfo();
            LLVM.InitializeX86AsmParser();
            LLVM.InitializeX86AsmPrinter();
        }

        public JIT() {
            
        }

        public int Execute(LLVMModuleRef module, string entrySymbol) {
            try {
                using var engine = module.CreateInterpreter();

                var entryRef = module.GetNamedFunction(entrySymbol);
               
                var args = new string[] { };
                var env = new string[] { };
                var returnVal = engine.RunFunctionAsMain(entryRef, 0, args, env);
                return returnVal;
            } catch (Exception ex) {
                Log.Error($"JIT execution error: {ex}");
            }
            return -1;
        }

        //public int Execute(LLVMModuleRef module, string entrySymbol) {
        //    try {
        //        using var engine = module.CreateMCJITCompiler();
        //        var entryRef = module.GetNamedFunction(entrySymbol);
        //        var entry = engine.GetPointerToGlobal<IntMain0>(entryRef);

        //        if (entry == null) {
        //            throw new CompileException($"Entry function {entrySymbol} not found");
        //        }
        //        var result = entry();
        //        return result;
        //    } catch (Exception ex) {
        //        Log.Error($"JIT execution error: {ex}");
        //    }
        //    return -1;
        //}
    }
}
