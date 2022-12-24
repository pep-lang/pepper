
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "llvm/Support/FormatVariadic.h"

namespace llvm {
    class Module;
}

namespace pepper {
    class ModuleContext;

    class Message {
        DECLARE_RTTI(Message);

      private:
        std::string Output = "";

      protected:
        virtual std::string prefix() const {
            return "";
        }

      public:
        template <typename... Args>
        Message(std::string_view fmt, Args&&... args) {
            Output = prefix() + std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...));
        }

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        Message(const Ctx& ctx, std::string_view fmt, Args&&... args) {
            Output = std::string(llvm::formatv("{0}: {1}", ctx.toString(), prefix())) +
                     std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...));
        }

        std::string message() const {
            return Output;
        }
    };

    struct Warning : public Message {
        DECLARE_RTTI(Warning, Message)
        using Message::Message;

        std::string prefix() const override {
            return "Warning: ";
        }
    };

    struct Error : public Message {
        DECLARE_RTTI(Error, Message)
        using Message::Message;

        std::string prefix() const override {
            return "ERROR: ";
        }
    };

    class Compiler {
      protected:
        std::string ModuleName;
        std::string SourcePath;

      public:
        static Ref<Compiler> Create(const std::string& moduleName);

        template <IsA<Message> T, typename... Args>
        void Report(std::string_view fmt, Args&&... args) {
            report(Ref<T>::New(fmt, std::forward<Args>(args)...));
        }

        virtual Ref<ModuleContext> compile(const std::string& sourceFile) = 0;
        virtual Ref<ModuleContext> compile(std::istream& sourceStream, const std::string& sourceFile = "<stream>") = 0;

        virtual void report(Ref<Message> msg) = 0;
    };
} // namespace pepper
