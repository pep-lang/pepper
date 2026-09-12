
#pragma once

#include "Core/Common.h"

#include "fmt/format.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper { namespace debug {
    struct FunctionTag {
        std::string_view fn;

        operator std::string_view() const {
            return fn;
        }
    };

    struct BasicTracer {
        size_t depth = 0;
        size_t prev_depth = 0;
        bool enabled = true;
        bool continue_line = false;

        static std::string_view strip_symbol(const std::string_view symbol) {
            const size_t colon_pos = symbol.rfind(':');
            if (colon_pos != std::string_view::npos) {
                return symbol.substr(colon_pos + 1);
            }
            return symbol;
        }

        void trace(FunctionTag fn) {
            trace(fmt::format("{}", strip_symbol(fn)));
        }

        void trace(const std::string& msg = "") {
            if (!enabled) {
                return;
            }
            if (!continue_line) {
                static const auto vert = "│ ";
                const auto prefix = depth > 0 ? "├-" : "";
                prev_depth = depth;
                std::string conn;
                for (size_t idx = 1; idx < depth; ++idx) {
                    conn += vert;
                }
                llvm::outs() << conn << prefix << msg;
                continue_line = true;
            } else {
                llvm::outs() << " " << msg;
            }

            llvm::outs().flush();
        }

        void traceln(const std::string& msg = {}) {
            if (!enabled) {
                return;
            }
            if (!msg.empty()) {
                trace(msg);
            }
            llvm::outs() << "\n";
            llvm::outs().flush();
            continue_line = false;
        }
    };

    struct TraceScope {
        BasicTracer* parent_tracer = nullptr;
        std::string name;
        bool is_inline = false;

        TraceScope(BasicTracer* t, const std::string_view tag)
            : parent_tracer(t)
              , name(tag) {}

        TraceScope(BasicTracer* t, const std::string_view tag, bool created_inline)
            : TraceScope(t, tag) {
            is_inline = created_inline;
        }

        TraceScope(const TraceScope&) = delete;
        TraceScope& operator=(const TraceScope&) = delete;

        TraceScope(TraceScope&& rhs) noexcept {
            std::swap(parent_tracer, rhs.parent_tracer);
            std::swap(name, rhs.name);
            std::swap(is_inline, rhs.is_inline);
        }

        //TraceScope& operator=(TraceScope&&) noexcept = default;

        virtual ~TraceScope() {}

        template <typename T>
        T* tracer() const {
            return static_cast<T*>(tracer());
        }

        BasicTracer* tracer() const {
            return parent_tracer;
        }
    };

    template <class T>
    concept TraceScopeDerived = std::derived_from<T, TraceScope>;

    template <TraceScopeDerived TScope=TraceScope>
    struct Tracer : BasicTracer {
        struct Scope : TScope {
            size_t depth = 0;

            Scope(BasicTracer* t, const std::string_view tag, bool created_inline)
                : TScope(t, tag) {
                this->is_inline = created_inline;
                depth = t->depth;
                // this->template tracer<Tracer>()->trace(fmt::format("PUSH {}: depth: {}", this->name, depth));
            }

            Scope(Scope&&) noexcept = default;

            ~Scope() {
                if (this->tracer() && !this->is_inline) {
                    this->template tracer<Tracer>()->pop();
                    // this->template tracer<Tracer>()->trace(fmt::format("POP  {}: depth: {}", this->name, depth));
                    auto cur_depth = this->tracer()->depth;
                    assert(depth == cur_depth);
                }
            }
        };

        auto top() {
            return Scope{this, "Top", true};
        }

        template <typename TName>
        auto scope(TName name, bool is_inline = true) {
            if (continue_line) {
                traceln();
            }
            trace(name);
            return Scope{this, {name}, is_inline};
        }

        template <typename TName>
        auto push(TName name) {
            // if (continue_line) {
            //     traceln();
            // }
            // traceln(fmt::format("PUSH {}: depth: {}", std::string_view{name}, depth));
            auto s = scope(name, false);
            ++depth;
            return std::move(s);
        }

        template <typename TName>
        auto pushln(TName name) {
            auto&& s = push(name);
            traceln();
            return std::move(s);
        }

        void pop() {
            assert(depth >= 1);
            --depth;
            if (continue_line)
                traceln();
        }
    };
}}
