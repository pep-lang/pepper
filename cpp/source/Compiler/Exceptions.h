
#pragma once

#include <exception>
#include <string>

class CompileError : public std::exception {
  private:
    std::string Message;

  public:
    CompileError(const std::string& msg)
        : Message(msg) {}

    const char* what() const noexcept override { return Message.c_str(); }
};

class InternalCompilerError : public std::exception {
  private:
    std::string Message;

  public:
    InternalCompilerError(const std::string& msg)
        : Message(msg) {}

    const char* what() const noexcept override { return Message.c_str(); }
}
