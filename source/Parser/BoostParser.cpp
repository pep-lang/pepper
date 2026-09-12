
#include "BoostParser.h"

namespace pepper::parser {


    std::unique_ptr<Module> parse(const std::string_view source) {
        namespace bp = boost::parser;
        const auto source_range = bp::detail::text::as_utf32(source);

        const auto report_error = [](const std::string& msg) {
            llvm::errs() << msg << '\n';
        };

        bp::callback_error_handler error_handler{report_error};

        // const auto parser = bp::with_error_handler(rules::module, error_handler);
        //
        // const auto result = [&] {
        //     try {
        //         return std::optional{bp::parse(source_range, parser, rules::ws, bp::trace::on)};
        //     } catch (std::exception& e) {
        //         llvm::errs() << e.what();
        //     }
        //     return std::optional<Module>{};
        // }();

        auto module_ast = std::make_unique<Module>();
        // TODO
        //(void)result;
        return module_ast;
    }



    class BoostParserImpl: public BoostParser {
        std::unique_ptr<ModuleNode> parse_tree = std::make_unique<ModuleNode>();
        std::unique_ptr<Module> parsed_module;
        const std::string source_file;
        const std::string source;
    public:
        BoostParserImpl(const std::string& _source_file, const std::string& _source)
            : source_file(_source_file), source(_source) {}

        ModuleNode* tree() const override {
            return parse_tree.get();
        }

        bool parse() override {
            parsed_module = parse_module();
            return !!parsed_module;
        }

        std::unique_ptr<Module> parse_module() const {

            auto module = parser::parse(source);
            return module;
        }
    };

    std::unique_ptr<BoostParser> BoostParser::create(const std::string& source_file, const std::string& source) {
        return std::make_unique<BoostParserImpl>(source_file, source);
    }
}