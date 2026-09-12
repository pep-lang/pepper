

#include "Core/Messages.h"

#include "llvm/Support/raw_ostream.h"

namespace pepper {
    Vector<Error> Messages::errs;
    Vector<Warning> Messages::warns;
    uint64_t Messages::channels;
    std::unordered_map<TraceChannel, std::string> Messages::indents;
    bool Messages::verbose_output = false;

    void Messages::report(Error&& msg) {
        llvm::errs() << msg.message() << "\n";
        llvm::errs().flush();
        errs.emplace_back(std::move(msg));
    }

    void Messages::report(Warning&& msg) {
        llvm::outs() << msg.message() << "\n";
        llvm::outs().flush();
        warns.emplace_back(std::move(msg));
    }

    void Messages::trace(TraceChannel channel, llvm::StringRef msg) {
        llvm::SmallString<256> buf(msg);
        const auto& indent = indents[channel];
        auto output = indent + replace_all(buf, "\n", "\n" + indent);
        llvm::outs() << output << "\n";
        llvm::outs().flush();
    }

    void Messages::verbose(llvm::StringRef msg) {
        llvm::outs() << msg << "\n";
    }
} // namespace pepper
