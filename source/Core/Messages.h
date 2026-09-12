
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
        std::string content = "";

      protected:
        virtual std::string prefix() const {
            return "";
        }

      public:
        template <typename... Args>
        Message(std::string_view fmt, Args&&... args) {
            content = prefix() + (sizeof...(args) ? std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...))
                                                  : std::string{fmt});
        }

        template <typename Ctx, typename... Args>
            requires HasToString<Ctx>
        Message(const Ctx& ctx, std::string_view fmt, Args&&... args) {
            content = std::string(llvm::formatv("{0}: {1}", ctx.to_string(), prefix())) +
                      std::string(llvm::formatv(fmt.data(), std::forward<Args>(args)...));
        }

        std::string message() const {
            return content;
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
        static Vector<Error> errs;
        static Vector<Warning> warns;
        static uint64_t channels;
        static std::unordered_map<TraceChannel, std::string> indents;
        static bool verbose_output;

      public:
        template <IsA<Message> M, HasToString Ctx, typename... Args>
        static void report(const Ctx& src, std::string_view fmt, Args&&... args) {
            report(std::move(M(src, fmt, std::forward<Args>(args)...)));
        }

        template <IsA<Message> M, typename... Args>
        static void report(std::string_view fmt, Args&&... args) {
            report(std::move(M(fmt, std::forward<Args>(args)...)));
        }

        static const Vector<Error>& errors() {
            return errs;
        }

        static const Vector<Warning>& warnings() {
            return warns;
        }

        static bool should_trace(TraceChannel channel) {
            return channels & uint64_t(channel);
        }

        static void indent(TraceChannel channel) {
            indents[channel] += "  ";
        }

        static void outdent(TraceChannel channel) {
            const auto& existing = indents[channel];
            if (existing.size() > 1)
                indents[channel] = existing.substr(0, existing.size() - 2);
        }

        static void set_trace_channels(uint64_t channels) {
            channels = channels;
        }

        static void set_trace_channels(TraceChannel channel) {
            set_trace_channels(uint64_t(channel));
        }

        static uint64_t get_trace_channels() {
            return channels;
        }

        static void trace(TraceChannel channel, llvm::StringRef msg);

        static void verbose(llvm::StringRef msg);

        static bool using_verbose_output() {
            return verbose_output;
        }

        static void enable_verbose_output(bool enable = true) {
            verbose_output = enable;
        }

      private:
        static void report(Error&& msg);

        static void report(Warning&& msg);
    };
} // namespace pepper

#define PEP_TRACING(channel) (Messages::should_trace(channel))

#define PEP_TRACE(channel, fmt, ...)                                                                                   \
    do {                                                                                                               \
        if (Messages::should_trace(channel)) {                                                                         \
            llvm::SmallString<256> msg(fmt);                                                                           \
            __VA_OPT__(msg = llvm::formatv(fmt, __VA_ARGS__));                                                         \
            Messages::trace(channel, msg);                                                                             \
        }                                                                                                              \
    } while (false);

#define PEP_VERBOSE(fmt, ...)                                                                                          \
    do {                                                                                                               \
        if (Messages::using_verbose_output()) {                                                                        \
            llvm::SmallString<256> msg(fmt);                                                                           \
            __VA_OPT__(msg = llvm::formatv(fmt, __VA_ARGS__));                                                         \
            Messages::verbose(msg);                                                                                    \
        }                                                                                                              \
    } while (false);
