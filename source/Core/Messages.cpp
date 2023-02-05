

#include "Core/Messages.h"

#include "llvm/Support/raw_ostream.h"

namespace pepper {
    Vector<Error> Messages::Errors;
    Vector<Warning> Messages::Warnings;
    uint64_t Messages::Channels;
    std::unordered_map<TraceChannel, std::string> Messages::Indents;
    bool Messages::VerboseOutput = false;

    void Messages::report(Error&& msg) {
        llvm::errs() << msg.message() << "\n";
        llvm::errs().flush();
        Errors.emplace_back(std::move(msg));
    }

    void Messages::report(Warning&& msg) {
        llvm::outs() << msg.message() << "\n";
        llvm::outs().flush();
        Warnings.emplace_back(std::move(msg));
    }

    void Messages::Trace(TraceChannel channel, llvm::StringRef msg) {
        llvm::SmallString<256> buf(msg);
        const auto& indent = Indents[channel];
        auto output = indent + replace_all(buf, "\n", "\n" + indent);
        llvm::outs() << output << "\n";
        llvm::outs().flush();
    }

    void Messages::Verbose(llvm::StringRef msg) {
        llvm::outs() << msg << "\n";
    }
} // namespace pepper
