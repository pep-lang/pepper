
#pragma once

#include <exception>
#include <format>
#include <string>

class CompileError : public std::exception {
  private:
    std::string Message;

  public:
    CompileError(const std::string& msg)
        : Message(msg) {}

    template <typename... Args>
    CompileError(std::string_view fmt, Args&&... args)
        : Message(std::vformat(fmt, std::make_format_args(args...))) {}

    const char* what() const noexcept override { return Message.c_str(); }
};

class InternalCompilerError : public std::exception {
  private:
    std::string Message;

  public:
    InternalCompilerError(const std::string& msg)
        : Message(msg) {}

    template <typename... Args>
    InternalCompilerError(std::string_view fmt, Args&&... args)
        : Message(std::vformat(fmt, std::make_format_args(args...))) {}

    const char* what() const noexcept override { return Message.c_str(); }
};
