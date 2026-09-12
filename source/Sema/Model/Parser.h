
#pragma once

#include "Module.h"
#include "Core/Common.h"
#include "Parser/Parser.h"

namespace pepper::sema {
    class Parser : public ParseState {
    public:
        static std::unique_ptr<Parser> create(const ParseState& state,
                                              Module* module,
                                              const parser::ModuleNode* parse_tree);

        Parser(const ParseState& state)
            : ParseState(state) {}

        virtual ~Parser() = default;
        virtual Module* ast() const = 0;
        virtual bool parse() = 0;
    };
}
