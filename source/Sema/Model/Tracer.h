
#pragma once

#include "Core/Common.h"
#include "Core/Vector.h"
#include "Core/Tracer.h"

#include "Parser/Parser.h"

#include "llvm/Support/TypeName.h"

namespace pepper { namespace sema {
    // type name parsing for tracing nodes
    namespace internal {
        template <typename T>
        struct type_name_impl {
            static std::string_view get() {
                return llvm::getTypeName<T>();
            }
        };

        template <typename BN, ConstString Name>
        struct type_name_impl<parser::BinaryExpressionNode<BN, Name>> {
            static std::string_view get() {
                return Name;
            }
        };

        template <typename T>
        static std::string_view type_name() {
            static const std::string_view raw_name = type_name_impl<T>::get();
            const size_t colon_pos = raw_name.rfind(':');
            if (colon_pos != std::string::npos) {
                return raw_name.substr(colon_pos + 1);
            }
            return raw_name;
        }

        static std::string_view function_name(std::string_view raw_name) {
            const size_t colon_pos = raw_name.rfind(':');
            if (colon_pos != std::string::npos) {
                return raw_name.substr(colon_pos + 1);
            }
            return raw_name;
        }
    }

    struct ParserScope : debug::TraceScope {
        using TraceScope::TraceScope;
    };

    struct ParserTracer : debug::Tracer<ParserScope> {
        Vector<ParserScope> stack;
        using Tracer::trace;

        void trace(const auto& node, const std::string& tag) {
            trace(fmt::format("{}: {}", tag, internal::type_name<std::decay_t<decltype(node)>>()));
        }

        void trace_val(const auto& node, const std::string& tag) {
            trace(fmt::format("{}({}): {}",
                              tag,
                              internal::type_name<std::decay_t<decltype(node)>>(),
                              visualize(node, 0)));
        }
    };
}}
