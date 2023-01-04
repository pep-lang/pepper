//
// Created by justi on 1/4/2023.
//

#include "Core/Messages.h"

#include "llvm/Support/raw_ostream.h"

namespace pepper {
    Vector<Error> Messages::Errors;
    Vector<Warning> Messages::Warnings;
    uint64_t Messages::Channels;
    std::unordered_map<TraceChannel, std::string> Messages::Indents;

    void Messages::report(Error&& msg) {
        llvm::errs() << msg.message() << "\n";
        Errors.emplace_back(std::move(msg));
    }

    void Messages::report(Warning&& msg) {
        llvm::outs() << msg.message() << "\n";
        Warnings.emplace_back(std::move(msg));
    }

    void Messages::Trace(TraceChannel channel, const std::string& msg) {
        const auto& indent = Indents[channel];
        auto output = indent + replace_all(msg, "\n", "\n" + indent);
        llvm::outs() << output << "\n";
    }
} // namespace pepper
