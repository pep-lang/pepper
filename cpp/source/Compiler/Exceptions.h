
#pragma once

#include <exception>
#include <format>
#include <string>

namespace pepper {
    template <typename T>
    concept HasToString = requires(T t) {
                              { t.toString() } -> std::same_as<std::string>;
                          };

    class CompileError : public std::exception {
      private:
        std::string Message;

      public:
        CompileError(const std::string& msg)
            : Message(msg) {
        }

        template <typename... Args>
        CompileError(std::string_view fmt, Args&&... args)
            : Message(std::vformat(fmt, std::make_format_args(args...))) {
        }

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        CompileError(const Ctx& ctx, std::string_view fmt, Args&&... args)
            : Message(std::format("{}: ", ctx.toString()) + std::vformat(fmt, std::make_format_args(args...))) {
        }

        const char* what() const noexcept override {
            return Message.c_str();
        }
    };

    class InternalCompilerError : public std::exception {
      private:
        std::string Message;

      public:
        InternalCompilerError(const std::string& msg)
            : Message(msg) {
        }

        template <typename... Args>
        InternalCompilerError(std::string_view fmt, Args&&... args)
            : Message(std::vformat(fmt, std::make_format_args(args...))) {
        }

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        InternalCompilerError(const Ctx& ctx, std::string_view fmt, Args&&... args)
            : Message(std::format("{}: ", ctx.toString()) + std::vformat(fmt, std::make_format_args(args...))) {
        }

        const char* what() const noexcept override {
            return Message.c_str();
        }
    };

} // namespace pepper
