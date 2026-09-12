
#pragma once

#include <iostream>
#include <list>
#include <string_view>
#include <vector>

#include "Core/Common.h"
#include "Core/Vector.h"
#include "fmt/format.h"

namespace pepper {

    namespace detail {
        // Extract the first type in a pack
        template <typename T, typename... Ts>
        struct first_type {
            using type = std::decay_t<T>;
        };

        template <typename... Ts>
        using first_type_t = typename first_type<Ts...>::type;
    } // namespace detail

    template <typename L>
    class BasicLexeme {
        uint32_t id;
        std::string_view name;

        static constexpr uint32_t name_to_id(std::string_view name) {
            uint32_t shift = 0;
            uint32_t res = 0;
            for (uint32_t idx = 0; idx < std::min<size_t>(4, name.length()); ++idx) {
                const char c = name[idx];
                res |= c << shift;
                shift += 8;
            }

            return name.length() > 4 ? res ^ name_to_id(name.substr(4)) : res;
        }

        static constexpr size_t const_strlen(const char* str) {
            size_t len = 0;
            const char* c = str;
            while (*c++ != '\0') {
                ++len;
            }
            return len;
        }

      public:
        constexpr BasicLexeme(std::string_view _name)
            : id(name_to_id(_name))
            , name(_name) {}

        constexpr BasicLexeme(const char* _name)
            : BasicLexeme({_name, const_strlen(_name)}) {}

        constexpr BasicLexeme(const BasicLexeme&) = default;
        constexpr BasicLexeme(BasicLexeme&) = delete;
        constexpr BasicLexeme& operator=(const BasicLexeme&) = default;

        constexpr operator uint32_t() const {
            return id;
        }

        constexpr std::string_view to_string() const {
            return name;
        }

        constexpr auto operator<=>(const BasicLexeme& rhs) const {
            return id <=> rhs.id;
        }

        constexpr operator L() {
            return *static_cast<L*>(this);
        }

        constexpr operator std::add_const_t<L>() const {
            return *static_cast<const L*>(this);
        }

        constexpr bool in(const Vector<L>& lexemes) const {
            for (const auto& lex : lexemes) {
                if (id == lex.id) {
                    return true;
                }
            }
            return false;
        }
    };

    struct Lexeme : BasicLexeme<Lexeme> {
        static constexpr BasicLexeme Plus{"+"};
        static constexpr BasicLexeme PlusEq{"+="};
        static constexpr BasicLexeme Plus2{"++"};
        static constexpr BasicLexeme Minus{"-"};
        static constexpr BasicLexeme MinusEq{"-="};
        static constexpr BasicLexeme Minus2{"--"};
        static constexpr BasicLexeme Star{"*"};
        static constexpr BasicLexeme StarEq{"*="};
        static constexpr BasicLexeme Star2{"**"};
        static constexpr BasicLexeme Slash{"/"};
        static constexpr BasicLexeme SlashEq{"/="};
        static constexpr BasicLexeme Percent{"%"};
        static constexpr BasicLexeme PercentEq{"%="};
        static constexpr BasicLexeme Ampersand{"&"};
        static constexpr BasicLexeme Ampersand2{"&&"};
        static constexpr BasicLexeme AmpersandEq{"&="};
        static constexpr BasicLexeme Pipe{"|"};
        static constexpr BasicLexeme Pipe2{"||"};
        static constexpr BasicLexeme PipeEq{"|="};
        static constexpr BasicLexeme Tilde{"~"};
        static constexpr BasicLexeme TildeEq{"~="};
        static constexpr BasicLexeme Caret{"^"};
        static constexpr BasicLexeme CaretEq{"^="};
        static constexpr BasicLexeme Less{"<"};
        static constexpr BasicLexeme LeftShift{"<<"};
        static constexpr BasicLexeme LeftShiftEq{"<<="};
        static constexpr BasicLexeme LessEq{"<="};
        static constexpr BasicLexeme Greater{">"};
        static constexpr BasicLexeme RightShift{">>"};
        static constexpr BasicLexeme RightShiftEq{">>="};
        static constexpr BasicLexeme GreaterEq{">="};
        static constexpr BasicLexeme Spaceship{"<=>"};
        static constexpr BasicLexeme Not{"!"};
        static constexpr BasicLexeme NotEq{"!="};
        static constexpr BasicLexeme NotEq2{"!=="};
        static constexpr BasicLexeme Equal{"="};
        static constexpr BasicLexeme Equal2{"=="};
        static constexpr BasicLexeme Equal3{"==="};
        static constexpr BasicLexeme LBrace{"{"};
        static constexpr BasicLexeme RBrace{"}"};
        static constexpr BasicLexeme LParen{"("};
        static constexpr BasicLexeme RParen{")"};
        static constexpr BasicLexeme LBracket{"["};
        static constexpr BasicLexeme RBracket{"]"};
        static constexpr BasicLexeme Dot{"."};
        static constexpr BasicLexeme Ellipsis{"..."};
        static constexpr BasicLexeme Comma{","};
        static constexpr BasicLexeme Colon{":"};
        static constexpr BasicLexeme Semicolon{";"};
        static constexpr BasicLexeme Newline{"\n"};
        static constexpr BasicLexeme Question{"?"};
        static constexpr BasicLexeme Dollar{"$"};
        static constexpr BasicLexeme At{"@"};

        static constexpr BasicLexeme IntLiteral{"int"};
        static constexpr BasicLexeme FloatLiteral{"float"};
        static constexpr BasicLexeme StringLiteral{"string"};
        static constexpr BasicLexeme RawStringLiteral{"raw_string"};
        static constexpr BasicLexeme BoolLiteral{"bool"};
        static constexpr BasicLexeme Keyword{"keyword"};
        static constexpr BasicLexeme Identifier{"identifier"};

        static constexpr BasicLexeme Whitespace{"whitespace"};

        static constexpr bool is_literal(const Lexeme& lex) {
            switch (lex) {
                case BoolLiteral:
                case IntLiteral:
                case FloatLiteral:
                case StringLiteral:
                case RawStringLiteral:
                    return true;
                default:
                    break;
            }
            return false;
        }

        static bool is_operator(const Lexeme& lex) {
            static const std::vector operators = {
                Plus,       PlusEq,    Plus2,   Minus,     MinusEq,   Minus2,     Star,        StarEq, Star2,
                Slash,      SlashEq,   Percent, PercentEq, Ampersand, Ampersand2, AmpersandEq, Pipe,   Pipe2,
                PipeEq,     Tilde,     TildeEq, Caret,     CaretEq,   Less,       LeftShift,   LessEq, Greater,
                RightShift, GreaterEq, Not,     NotEq,     Equal,     Equal2,     Equal3,
            };
            return std::find(operators.begin(), operators.end(), lex) != operators.end();
        }

        static bool is_prefix_operator(const Lexeme& lex) {
            switch (lex) {
                case Not:
                case Minus:
                case Plus:
                case Plus2:
                case Minus2:
                case Tilde:
                    return true;
                default:
                    break;
            }
            return false;
        }

        static bool is_postfix_operator(const Lexeme& lex) {
            switch (lex) {
                case Plus2:
                case Minus2:
                    return true;
                default:
                    break;
            }
            return false;
        }

        static bool is_assignment_operator(const Lexeme& lex) {
            switch (lex) {
                case Equal:
                case PlusEq:
                case MinusEq:
                case StarEq:
                case PercentEq:
                case SlashEq:
                case RightShiftEq:
                case LeftShiftEq:
                case AmpersandEq:
                case CaretEq:
                case PipeEq:
                    return true;
            }
            return false;
        }

        static Lexeme bracket_pair(const Lexeme& b) {
            switch (b) {
                case LBrace:
                    return RBrace;
                case LParen:
                    return RParen;
                case Less:
                    return Greater;
                case LBracket:
                    return RBracket;
                case RBrace:
                    return LBrace;
                case RParen:
                    return LParen;
                case Greater:
                    return Less;
                case RBracket:
                    return LBracket;
                default:
                    assert(!"Invalid lexeme passed to bracket_pair");
                    break;
            }
            PEP_UNREACHABLE();
        }
    };

    template <typename T>
    struct hash;

    template <>
    struct hash<Lexeme> {
        std::size_t operator()(const Lexeme& lex) const {
            static std::hash<uint32_t> impl;
            return impl(lex);
        }
    };

    static const std::vector<std::string_view> keywords{"as",
                                                        "break",
                                                        "continue",
                                                        "default",
                                                        "else",
                                                        "extend",
                                                        "extern",
                                                        "for",
                                                        "if",
                                                        "in",
                                                        "is",
                                                        "let",
                                                        "return",
                                                        "static",
                                                        "struct",
                                                        "use",
                                                        "var",
                                                        "while",
                                                        "with"};

    // Note that both line and column are 1-based (when shown to user)
    // and will need fixup (e.g. -1) when used to index into lines/text
    struct SourcePosition {
        uint32_t line = 0;
        uint32_t column = 0;

        auto operator<=>(const SourcePosition&) const = default;
    };

    class Token {
        Lexeme lex_type;
        std::string_view str;
        SourcePosition source;

      public:
        Token(const Lexeme& ty, std::string_view txt, const SourcePosition& loc)
            : lex_type(ty)
            , str(txt)
            , source(loc) {}

        Token(const Token&) = default;
        Token(Token&&) = default;
        Token& operator=(const Token&) = default;

        operator std::string_view() const {
            assert(str.data());
            return str;
        }

        auto operator<=>(const Token& t) const {
            if (auto cmp = lex_type <=> t.lex_type; cmp != 0) {
                return cmp;
            }
            return str <=> t.str;
        }

        auto operator==(const Lexeme& lex) const {
            return lex_type == lex;
        }

        auto operator==(const std::string_view& sv) const {
            return str == sv;
        }

        const SourcePosition& location() const {
            return source;
        }

        auto length() const {
            return str.length();
        }

        auto type() const {
            return lex_type;
        }

        auto text() const {
            return str;
        }

        template <typename... Values>
        bool in(Values&&... values) const
            requires std::is_same_v<detail::first_type_t<Values...>, BasicLexeme<Lexeme>> ||
                     std::is_constructible_v<std::string_view, detail::first_type_t<Values...>>
        {
            using V = detail::first_type_t<Values...>;
            using Elem = std::conditional_t<std::is_constructible_v<std::string_view, V>, std::string_view, Lexeme>;
            return in(Vector<Elem>{std::forward<Values>(values)...});
        }

        bool in(const Vector<Lexeme>& lexemes) const {
            return lex_type.in(lexemes);
        }

        std::string to_string() const {
            const bool is_string = (lex_type.in({Lexeme::RawStringLiteral, Lexeme::StringLiteral}));
            const bool is_raw = is_string && lex_type == Lexeme::RawStringLiteral;
            if (is_string) {
                return fmt::format("{}\"{}\"", is_raw ? "@" : "", str);
            }

            return std::string(str);
        }

        void visit(auto& visitor) const {
            visitor.visit(*this);
        }

      private:
        bool in(const Vector<std::string_view>& values) const {
            for (auto value : values) {
                if (str == value) {
                    return true;
                }
            }
            return false;
        }
    };

    struct Comment {
        std::string str;
        SourcePosition start;
        SourcePosition end;
    };

    struct ParseError {
        const SourcePosition where;
        const std::string what;
    };

    // shared state between lexer and Parser
    struct ParseState {
        std::string source_file;
        std::vector<Token> tokens;
        std::vector<Comment> comments;
        std::vector<ParseError> errors;
        std::list<std::string> strings;
    };

    inline bool is_digit(char c) {
        return std::isdigit(c);
    }

    inline bool is_binary_digit(char c) {
        return c == '0' || c == '1';
    }

    inline bool is_hex_digit(char c) {
        return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    inline bool is_ascii_underscore(char c) {
        return isalpha(c) || c == '_';
    }

    inline size_t is_identifier_rest(char c) {
        return is_ascii_underscore(c) || is_digit(c);
    }

    inline size_t is_identifier(std::string_view s) {
        if (is_ascii_underscore(s[0])) {
            size_t idx = 1;
            while (is_identifier_rest(s[idx])) {
                ++idx;
            }
            return idx;
        }
        return 0;
    }

    inline bool is_whitespace(char c) {
        return isspace(c);
    }

    class Lexer : public ParseState {
        struct {
            bool open = false;
            std::string buffer;
            SourcePosition start;
            bool raw = false;
        } string_state;

        bool lex_line(const std::string& line, const uint32_t line_num) {
            uint32_t column = 0;
            const auto tokens_before = std::ssize(tokens);

            auto peek = [&](int offset) {
                return (column + offset < std::ssize(line) && column + offset >= 0) ? line[column + offset] : '\0';
            };

            auto scan_digits = [&](auto pos) {
                while (is_digit(line[column + pos])) {
                    ++pos;
                }
                return pos;
            };

            auto scan_whitespace = [&] {
                ssize_t pos = 0;
                while (is_whitespace(line[column + pos])) {
                    ++pos;
                }
                return pos;
            };

            auto store = [&](size_t length, const Lexeme& type) {
                tokens.emplace_back(Token{type, {&line[column], length}, SourcePosition{line_num, column + 1}});
                auto& t = tokens.back();
                column += length - 1; // will get incremented at end of loop
            };

            // auto peek_escape_seq = [&](int offset) {
            //     auto peek1 = peek(offset);
            //     auto peek2 = peek(offset + 1);
            //     if (peek1 == '\\' && peek2 == 'x') {
            //         return 2;
            //     }
            //     return 0;
            // };

            auto peek_keyword = [&]() -> ssize_t {
                auto remaining = std::string_view(line).substr(column);
                auto kw = std::find_if(keywords.begin(), keywords.end(), [&](std::string_view s) {
                    // keyword must be followed by space
                    return remaining.starts_with(s) && is_whitespace(remaining[s.length()]);
                });
                if (kw != keywords.end()) {
                    return std::ssize(*kw);
                }
                return 0;
            };

            for (; column < ssize(line); ++column) {
                auto peek1 = peek(1);
                auto peek2 = peek(2);
                auto peek3 = peek(3);

                if (string_state.open) {
                    // look for the ending "
                    if (const auto pos = line.find('"', column); pos != std::string::npos) {
                        if (line[pos - 1] != '\\') {
                            string_state.buffer.append(line.begin() + column, line.begin() + pos);
                            strings.push_back(std::move(string_state.buffer));
                            const auto& str = strings.back();
                            tokens.emplace_back(string_state.raw ? Lexeme::RawStringLiteral : Lexeme::StringLiteral,
                                                str,
                                                string_state.start);
                            string_state = {};
                            column = pos;
                        } else {
                            // just collect the rest of the line into the current string buffer
                            string_state.buffer.append(line.begin(), line.end());
                            string_state.buffer += "\n";
                            column = ssize(line) - 1;
                        }
                    }
                } else {
                    switch (line[column]) {
                        case '#': {
                            // Skip the rest of the line, there's nothing to parse, leave the newline to be stored
                            column = std::ssize(line) - 1;
                            break;
                        }
                        case '/': {
                            if (peek1 == '=') {
                                store(2, Lexeme::SlashEq);
                            } else {
                                store(1, Lexeme::Slash);
                            }
                            break;
                        }
                        case '<': {
                            if (peek1 == '<') {
                                if (peek2 == '=') {
                                    store(3, Lexeme::LeftShiftEq);
                                } else {
                                    store(2, Lexeme::LeftShift);
                                }
                            } else if (peek1 == '=') {
                                store(2, Lexeme::LessEq);
                            } else {
                                store(1, Lexeme::Less);
                            }
                            break;
                        }
                        case '>': {
                            // NOTE: >> and >>= cannot be lexed, they get figured out by the Parser
                            if (peek1 == '=') {
                                store(2, Lexeme::GreaterEq);
                            } else {
                                store(1, Lexeme::Greater);
                            }
                            break;
                        }
                        case '+': {
                            if (peek1 == '+') {
                                store(2, Lexeme::Plus2);
                            } else if (peek1 == '=') {
                                store(2, Lexeme::PlusEq);
                            } else {
                                store(1, Lexeme::Plus);
                            }
                            break;
                        }
                        case '-': {
                            if (peek1 == '-') {
                                store(2, Lexeme::Plus2);
                            } else if (peek1 == '=') {
                                store(2, Lexeme::MinusEq);
                            } else {
                                store(1, Lexeme::Minus);
                            }
                            break;
                        }
                        case '|': {
                            if (peek1 == '|') {
                                store(2, Lexeme::Pipe2);
                            } else if (peek1 == '=') {
                                store(2, Lexeme::PipeEq);
                            } else {
                                store(1, Lexeme::Pipe);
                            }
                            break;
                        }
                        case '&': {
                            if (peek1 == '&') {
                                store(2, Lexeme::Ampersand2);
                            } else if (peek1 == '=') {
                                store(2, Lexeme::AmpersandEq);
                            } else {
                                store(1, Lexeme::Ampersand);
                            }
                            break;
                        }
                        case '*': {
                            if (peek1 == '=') {
                                store(2, Lexeme::StarEq);
                            } else if (peek1 == '*') {
                                store(2, Lexeme::Star2);
                            } else {
                                store(1, Lexeme::Star);
                            }
                            break;
                        }
                        case '%': {
                            if (peek1 == '=') {
                                store(2, Lexeme::PercentEq);
                            } else {
                                store(1, Lexeme::Percent);
                            }
                            break;
                        }
                        case '^': {
                            if (peek1 == '=') {
                                store(2, Lexeme::CaretEq);
                            } else {
                                store(1, Lexeme::Caret);
                            }
                            break;
                        }
                        case '~': {
                            if (peek1 == '=') {
                                store(2, Lexeme::TildeEq);
                            } else {
                                store(1, Lexeme::Tilde);
                            }
                            break;
                        }
                        case '=': {
                            if (peek2 == '=') {
                                store(3, Lexeme::Equal3);
                            } else if (peek1 == '=') {
                                store(2, Lexeme::Equal2);
                            } else {
                                store(1, Lexeme::Equal);
                            }
                            break;
                        }
                        case '!': {
                            if (peek1 == '=') {
                                if (peek2 == '=') {
                                    store(3, Lexeme::NotEq2);
                                } else {
                                    store(2, Lexeme::NotEq);
                                }
                            } else {
                                store(1, Lexeme::Not);
                            }
                            break;
                        }
                        case '.': {
                            if (peek1 == '.' && peek2 == '.') {
                                store(3, Lexeme::Ellipsis);
                            } else {
                                store(1, Lexeme::Dot);
                            }
                            break;
                        }
                        case ':': {
                            store(1, Lexeme::Colon);
                            break;
                        }
                        case '{': {
                            store(1, Lexeme::LBrace);
                            break;
                        }
                        case '}': {
                            store(1, Lexeme::RBrace);
                            break;
                        }
                        case '(': {
                            store(1, Lexeme::LParen);
                            break;
                        }
                        case ')': {
                            store(1, Lexeme::RParen);
                            break;
                        }
                        case '[': {
                            store(1, Lexeme::LBracket);
                            break;
                        }
                        case ']': {
                            store(1, Lexeme::RBracket);
                            break;
                        }
                        case ';': {
                            store(1, Lexeme::Semicolon);
                            break;
                        }
                        case ',': {
                            store(1, Lexeme::Comma);
                            break;
                        }
                        case '?': {
                            store(1, Lexeme::Question);
                            break;
                        }
                        case '@': {
                            if (peek1 == '"') {
                                column += 1; // skip '@'
                                string_state.open = true;
                                string_state.start = {line_num, column + 1};
                                string_state.raw = true;
                                break;
                            }
                            store(1, Lexeme::At);
                            break;
                        }
                        case '$': {
                            store(1, Lexeme::Dollar);
                            break;
                        }
                        // parse literals
                        case '0': {
                            int pos = 3;
                            if (peek1 == 'b') {
                                if (is_binary_digit(peek2)) {
                                    // consume the rest of the literal and call it good
                                    while (is_binary_digit(peek(pos))) {
                                        ++pos;
                                    }
                                    store(pos, Lexeme::IntLiteral);
                                    continue;
                                } else {
                                    report_error(SourcePosition{line_num, column},
                                                 "0b binary literal must have a value");
                                    ++column;
                                }
                            } else if (peek1 == 'x') {
                                if (is_hex_digit(peek2)) {
                                    // consume the rest of the literal and call it good
                                    while (is_hex_digit(peek(pos))) {
                                        ++pos;
                                    }
                                    store(pos, Lexeme::IntLiteral);
                                    continue;
                                } else {
                                    report_error(SourcePosition{line_num, column}, "0x hex literal must have a value");
                                    ++column;
                                }
                            }
                        }
                            [[fallthrough]];
                        default: {
                            // numeric literals
                            if (is_digit(line[column])) {
                                int pos = 1;
                                pos = scan_digits(pos);
                                if (peek(pos) != '.') {
                                    store(pos, Lexeme::IntLiteral);
                                } else {
                                    if (peek(pos) == '.') {
                                        ++pos;
                                        if (!is_digit(peek(pos))) {
                                            report_error(SourcePosition{line_num, column},
                                                         "floating point literals must have at least one "
                                                         "digit after the decimal point");
                                        }
                                        pos = scan_digits(pos);
                                    }

                                    if (peek(pos) == 'e') {
                                        ++pos;
                                        if (peek(pos) == '-' || peek(pos) == '+') {
                                            ++pos;
                                        }
                                        pos = scan_digits(pos);
                                    }
                                    store(pos, Lexeme::FloatLiteral);
                                }
                            }
                            // string literal start, gets finished above
                            else if (line[column] == '"') {
                                string_state.open = true;
                                string_state.start = {line_num, column};
                            }
                            // keywords
                            else if (auto pos = peek_keyword()) {
                                store(pos, Lexeme::Keyword);
                            }
                            // identifiers
                            else if (auto pos = is_identifier({&line[column], std::size(line) - column})) {
                                std::string_view identifier(&line[column], std::size(line) - column);
                                if (identifier == "true" || identifier == "false") {
                                    store(pos, Lexeme::BoolLiteral);
                                } else {
                                    store(pos, Lexeme::Identifier);
                                }
                            }
                            // what remains _should_ be whitespace
                            else if (auto pos = scan_whitespace()) {
                                store(pos, Lexeme::Whitespace);
                            } else {
                                report_error(SourcePosition{line_num, column},
                                             std::string("Unexpected token '") + line[column] + "'");
                            }
                        }
                    }
                }
            }
            store(1, Lexeme::Newline);

            assert(std::ssize(tokens) >= tokens_before);
            return std::ssize(tokens) != tokens_before;
        }

        void report_error(SourcePosition loc, const std::string& msg) {
            errors.emplace_back(ParseError{loc, msg});
        }

      public:
        Lexer(const std::string source_name) {
            source_file = source_name;
        }

        void lex(const Vector<std::string>& lines) {
            auto line = std::begin(lines);
            while (line != std::end(lines)) {
                auto line_num = std::distance(std::begin(lines), line) + 1;

                for (; line != std::end(lines); ++line, ++line_num) {
                    lex_line(*line, line_num);
                }
            }
        }

        void print() const {
            auto line = tokens[0].location().line;
            for (const auto& token : tokens) {
                // Emit newline when token line number changes
                if (token.location().line > line) {
                    line = token.location().line;
                    std::cout << std::endl;
                }

                const bool is_string_literal = token.in(Lexeme::RawStringLiteral, Lexeme::StringLiteral);
                if (is_string_literal) {
                    if (token == Lexeme::RawStringLiteral) {
                        std::cout << "@";
                    }
                    std::cout << '"';
                }

                std::cout << std::string_view(token);

                if (is_string_literal) {
                    std::cout << '"';
                }
            }
            std::cout << std::endl;
            std::flush(std::cout);
        }
    };
} // namespace pepper
