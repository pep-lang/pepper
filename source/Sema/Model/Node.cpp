

#include "Sema/Model/Node.h"
#include <regex>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Sema/Model/Block.h"
#include "Sema/Model/Visitor.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::sema {
    Vector<SourceLocation> Node::SourceStack;

    void Node::push_source(const SourceLocation& source) {
        SourceStack.emplace_back(source);
        CompileError::Source = source;
    }

    void Node::pop_source() {
        assert(SourceStack.size() > 0);

        SourceStack.pop_back();

        CompileError::Source = SourceStack.empty() ? SourceLocation{} : get_source_location();
    }

    SourceLocation Node::get_source_location() {
        if (SourceStack.empty()) {
            throw InternalCompilerError("No source location available to construct Sema node");
        }
        return SourceStack.back();
    }

    Node::Node()
        : source_loc(get_source_location()) {
        NodeHeap::track(this);
    }

    Node::~Node() {
        // PEP_TRACE(TraceChannel::AST, "~Node: {0}", this);
    }

    std::string Node::source(int width, int indent, const char* sep) const {
        if (source_loc.file.empty()) {
            return {""};
        }
        width = (width >= 0) ? width : (int)source_loc.file.size() + 10;
        width += indent;
        std::string src = source_loc.to_string();
        std::string padding = repeat(" ", width - src.size());
        return llvm::formatv("{0}{1}{2}", src, sep, padding);
    }

    std::string Node::node_name() const {
        return std::string{rtti()->name()};
    }

    std::string Node::to_string() const {
        return llvm::formatv("{0}", rtti()->name());
    }

    std::string Node::dump(int indent) const {
        return llvm::formatv("{0}{1}", repeat(" ", indent), rtti()->name());
    }

    Node* Node::clone() const {
        return ((const RttiInstance<Node>*)rtti())->clone(this);
    }

    void Node::visit(struct Visitor& visitor) {}

    std::list<std::unique_ptr<Node>> NodeHeap::FloatingNodes;

    void NodeHeap::track(Node* node) {
        FloatingNodes.emplace_back(node);
    }

    void NodeHeap::clear() {
        FloatingNodes.clear();
    }

    void Symbol::visit(Visitor& visitor) {
        Node::visit(visitor);
        visitor.visit(type);
    }

    void Visitor::visit(struct TypeName& type) {
        visitType(type);
    }

    void Visitor::visit(NodeRef& ref) {
        if (!ref || visited.contains(ref))
            return;
        visited.insert(ref);

        if (auto block = ref->as<Block>()) {
            stack.emplace_back(block);
        }

        Node::push_source(ref->source_loc);

        enterNode(ref);
        visitNode(ref);
        ref->visit(*this);
        exitNode(ref);

        Node::pop_source();

        if (auto block = ref->as<Block>()) {
            assert(stack.back() == block && "Mismatched Block stack in Visitor");
            stack.pop_back();
        }
    }

    void Visitor::visit(Node* node) {
        auto ref = NodeRef::temp(node);
        visit(ref);
    }

} // namespace pepper::sema
