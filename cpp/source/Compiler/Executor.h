
#include "Core/Common.h"
#include <string>

namespace llvm {
    class Module;
}

namespace pepper {
    class Executor {
      protected:
        Executor() = default;

      public:
        static Ref<Executor> Create();

        virtual ~Executor() = default;

        virtual llvm::Module* createModule(const std::string& name) = 0;

        virtual int Execute(const std::string& entry = "main") = 0;
        // virtual int Interpret(llvm::Module* module, const std::string& entry = "main") = 0;
    };
} // namespace pepper
