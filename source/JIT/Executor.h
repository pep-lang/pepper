#pragma once

#include <any>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"

#pragma push_macro("min")
#pragma push_macro("max")
#undef min
#undef max
#include "llvm/ExecutionEngine/Orc/Shared/ExecutorAddress.h"
#pragma pop_macro("min")
#pragma pop_macro("max")

namespace pepper {
    class LLVMModuleGenerator;
    class Runtime;

    class Executor {
      protected:
        Executor() = default;

      public:
        static Ref<Executor> create();

        virtual ~Executor() = default;

        // Run a function in the module. Note that the JIT will take ownership of the module
        // so it is dead after this function is called
        // virtual std::any execute(Ref<LLVMModuleGenerator> context, const std::string& entry = "main") = 0;
        // virtual void prepare(Ref<LLVMModuleGenerator> context) = 0;
        // template <typename T = int>
        // T execute(Ref<LLVMModuleGenerator> context, const std::string& entry = "main") {
        //     prepare(context);
        //     return execute<T>(entry);
        // }

        virtual void prepare(const Vector<std::string>& obj_files) = 0;
        virtual std::any execute(const Vector<std::string>& obj_files, const std::string& entry = "main") = 0;
        virtual void execute_entry(const std::string& entry,
                                   std::function<void(const llvm::orc::ExecutorAddr&)>&& exec) = 0;

        template <typename T = int>
        T invoke(const std::string& entry = "main") {
            T result;
            execute_entry(entry, [&result](const llvm::orc::ExecutorAddr& fn) {
                auto fn_ptr = fn.toPtr<T()>();
                result = fn_ptr();
            });
            return result;
        }

        template <typename T = int>
        T invoke(const Vector<std::string>& obj_files, const std::string& entry = "main") {
            prepare(obj_files);
            return invoke<T>(entry);
        }
    };
} // namespace pepper
