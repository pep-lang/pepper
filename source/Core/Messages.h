//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
#include "Core/String.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {
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

    enum class TraceChannel : uint64_t {
        AST = 1 << 0,
        Codegen = 1 << 1,
        Parser = 1 << 2,
        IR = 1 << 3,
        ALL = 0xffffffff,
        NONE = 0,
    };

    class Messages {
        static auto& _errors() {
            static Vector<Error> Errors;
            return Errors;
        }

        static auto& _warnings() {
            static Vector<Warning> Warnings;
            return Warnings;
        }

        static auto& _traceChannels() {
            static uint64_t channels = 0;
            return channels;
        }

        static auto& _indents() {
            static std::unordered_map<TraceChannel, std::string> Indents;
            return Indents;
        }

      public:
        template <IsA<Message> M, HasToString Ctx, typename... Args>
        static void Report(const Ctx& src, std::string_view fmt, Args&&... args) {
            report(std::move(M(src, fmt, std::forward<Args>(args)...)));
        }

        template <IsA<Message> M, typename... Args>
        static void Report(std::string_view fmt, Args&&... args) {
            report(std::move(M(fmt, std::forward<Args>(args)...)));
        }

        static const Vector<Error>& errors() {
            return _errors();
        }

        static const Vector<Warning>& warnings() {
            return _warnings();
        }

        static bool ShouldTrace(TraceChannel channel) {
            return _traceChannels() & uint64_t(channel);
        }

        static void Indent(TraceChannel channel) {
            _indents()[channel] += "  ";
        }

        static void Outdent(TraceChannel channel) {
            const auto& existing = _indents()[channel];
            if (existing.size() > 1)
                _indents()[channel] = existing.substr(0, existing.size() - 2);
        }

        static void SetTraceChannels(uint64_t channels) {
            _traceChannels() = channels;
        }

        static void SetTraceChannels(TraceChannel channel) {
            SetTraceChannels(uint64_t(channel));
        }

        static uint64_t GetTraceChannels() {
            return _traceChannels();
        }

        static void Trace(TraceChannel channel, const std::string& msg) {
            const auto& indent = _indents()[channel];
            auto output = indent + replace_all(msg, "\n", "\n" + indent);
            std::cout << output << std::endl;
        }

      private:
        static void report(Error&& msg) {
            std::cout << msg.message() << std::endl;
            _errors().emplace_back(std::move(msg));
        }

        static void report(Warning&& msg) {
            std::cout << msg.message() << std::endl;
            _warnings().emplace_back(std::move(msg));
        }
    };
} // namespace pepper

#define PEP_TRACING(channel) (Messages::ShouldTrace(channel))

#define PEP_TRACE(channel, fmt, ...)                                                                                   \
    if (Messages::ShouldTrace(channel)) {                                                                              \
        std::string msg(fmt);                                                                                          \
        __VA_OPT__(msg = llvm::formatv(fmt, __VA_ARGS__));                                                             \
        Messages::Trace(channel, msg);                                                                                 \
    }
