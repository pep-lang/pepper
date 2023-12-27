
#pragma once

#include <exception>
#include <memory>
#include <string>

#include "Core/Common.h"
#include "Core/SourceLocation.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {

    class CompileError : public std::exception {
      private:
        std::string Message;

      public:
        CompileError(const std::string& msg)
            : Message(std::string(llvm::formatv("{0}: {1}", Source.toString(), msg))) {}

        template <typename... Args>
        CompileError(std::string_view fmt, Args&&... args)
            : Message(std::string(llvm::formatv("{0}: ", Source.toString())) +
                      std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        CompileError(const Ctx& ctx, std::string_view fmt, Args&&... args)
            : Message(std::string(llvm::formatv("{0}: ", ctx.toString())) +
                      std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

        const char* what() const noexcept override {
            return Message.c_str();
        }

        static SourceLocation Source;
    };

    class InternalCompilerError : public std::exception {
      private:
        std::string Message;

      public:
        InternalCompilerError(const std::string& msg)
            : Message(msg) {}

        template <typename... Args>
        InternalCompilerError(std::string_view fmt, Args&&... args)
            : Message(llvm::formatv(fmt.data(), std::forward<Args>(args)...)) {}

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        InternalCompilerError(const Ctx& ctx, std::string_view fmt, Args&&... args)
            : Message(std::string(llvm::formatv("%s: ", ctx.toString())) +
                      std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

        const char* what() const noexcept override {
            return Message.c_str();
        }
    };

} // namespace pepper
