//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/raw_ostream.h"

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
        DebugInfo = 1 << 4,
        Link = 1 << 5,
        ALL = 0xffffffff,
        NONE = 0,
    };

    class Messages {
        static Vector<Error> Errors;
        static Vector<Warning> Warnings;
        static uint64_t Channels;
        static std::unordered_map<TraceChannel, std::string> Indents;
        static bool VerboseOutput;

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
            return Errors;
        }

        static const Vector<Warning>& warnings() {
            return Warnings;
        }

        static bool ShouldTrace(TraceChannel channel) {
            return Channels & uint64_t(channel);
        }

        static void Indent(TraceChannel channel) {
            Indents[channel] += "  ";
        }

        static void Outdent(TraceChannel channel) {
            const auto& existing = Indents[channel];
            if (existing.size() > 1)
                Indents[channel] = existing.substr(0, existing.size() - 2);
        }

        static void SetTraceChannels(uint64_t channels) {
            Channels = channels;
        }

        static void SetTraceChannels(TraceChannel channel) {
            SetTraceChannels(uint64_t(channel));
        }

        static uint64_t GetTraceChannels() {
            return Channels;
        }

        static void Trace(TraceChannel channel, llvm::StringRef msg);

        static void Verbose(llvm::StringRef msg);

        static bool OutputVerbose() {
            return VerboseOutput;
        }

        static void EnableVerbose(bool enable = true) {
            VerboseOutput = enable;
        }

      private:
        static void report(Error&& msg);

        static void report(Warning&& msg);
    };
} // namespace pepper

#define PEP_TRACING(channel) (Messages::ShouldTrace(channel))

#define PEP_TRACE(channel, fmt, ...)                                                                                   \
    do {                                                                                                               \
        if (Messages::ShouldTrace(channel)) {                                                                          \
            llvm::SmallString<256> msg(fmt);                                                                           \
            __VA_OPT__(msg = llvm::formatv(fmt, __VA_ARGS__));                                                         \
            Messages::Trace(channel, msg);                                                                             \
        }                                                                                                              \
    } while (false);

#define PEP_VERBOSE(fmt, ...)                                                                                          \
    do {                                                                                                               \
        if (Messages::OutputVerbose()) {                                                                               \
            llvm::SmallString<256> msg(fmt);                                                                           \
            __VA_OPT__(msg = llvm::formatv(fmt, __VA_ARGS__));                                                         \
            Messages::Verbose(msg);                                                                                    \
        }                                                                                                              \
    } while (false);
