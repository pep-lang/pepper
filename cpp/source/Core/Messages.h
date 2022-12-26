//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
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

    class Messages {
        static auto& _errors() {
            static Vector<Error> Errors;
            return Errors;
        }

        static auto& _warnings() {
            static Vector<Warning> Warnings;
            return Warnings;
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
