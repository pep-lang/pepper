using LLVMSharp.Interop;
using System.Runtime.InteropServices;

namespace Pepper {
    public unsafe class Executor {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate Int32 IntMain0();

        static Executor() {
            LLVM.LinkInMCJIT();
            LLVM.InitializeX86TargetMC();
            LLVM.InitializeX86Target();
            LLVM.InitializeX86TargetInfo();
            LLVM.InitializeX86AsmParser();
            LLVM.InitializeX86AsmPrinter();
        }

        public Executor() {

        }

        public int Interpret(LLVMModuleRef module, string entrySymbol) {
            try {
                using var engine = module.CreateInterpreter();

                var entryRef = module.GetNamedFunction(entrySymbol);

                var args = new LLVMGenericValueRef[] { };
                var env = new string[] { };
                var returnGV = engine.RunFunction(entryRef, args);
                var returnVal = (int)LLVM.GenericValueToInt(returnGV, 1);

                sbyte* errorPtr;
                LLVM.ExecutionEngineGetErrMsg(engine, &errorPtr);
                var error = new string((char*)errorPtr);
                LLVM.DisposeErrorMessage(errorPtr);

                return returnVal;
            } catch (Exception ex) {
                Log.Error($"JIT execution error: {ex}");
            }
            return -1;
        }

        public int Execute(LLVMModuleRef module, string entrySymbol) {
            try {
                using var engine = module.CreateMCJITCompiler();
                var entryRef = module.GetNamedFunction(entrySymbol);
                var entry = engine.GetPointerToGlobal<IntMain0>(entryRef);
                if (entry == null) {
                    throw new CompileException($"Entry function {entrySymbol} not found");
                }
                var result = entry();
                return result;
            } catch (Exception ex) {
                Log.Error($"JIT execution error: {ex}");
            }
            return -1;
        }
    }
}
