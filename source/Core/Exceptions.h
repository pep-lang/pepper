
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

        static std::string format(const SourceLocation& source, const std::string& msg);

      public:
        CompileError(const std::string& msg)
            : Message(format(Source, msg)) {}

        template <typename... Args>
        CompileError(std::string_view fmt, Args&&... args)
            : Message(format(Source, llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

        template <typename... Args>
        CompileError(const SourceLocation& source, std::string_view fmt, Args&&... args)
            : Message(format(source, llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

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
            : Message(std::string(llvm::formatv("%s: ", ctx.to_string())) +
                      std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...))) {}

        const char* what() const noexcept override {
            return Message.c_str();
        }
    };

} // namespace pepper
