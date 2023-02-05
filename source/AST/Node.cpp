

#include "AST/Node.h"
#include <regex>

#include "AST/Visitor.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/ADT/StringSet.h"

namespace pepper::ast {
    SourceLocation Node::TokenSource;

    Node::Node()
        : Source(TokenSource) {
        NodeHeap::Track(this);
    }

    Node::~Node() {
        // PEP_TRACE(TraceChannel::AST, "~Node: {0}", this);
    }

    std::string Node::source(int width, int indent, const char* sep) const {
        if (Source.File.empty()) {
            return {""};
        }
        width = (width >= 0) ? width : (int)Source.File.size() + 10;
        width += indent;
        std::string src = Source.toString();
        std::string padding = repeat(" ", width - src.size());
        return llvm::formatv("{0}{1}{2}", src, sep, padding);
    }

    std::string Node::toString() const {
        return llvm::formatv("{0}: ", rtti()->name());
    }

    std::string Node::dump(int indent) const {
        return llvm::formatv("{0}{1}", repeat(" ", indent), rtti()->name());
    }

    Node* Node::clone() const {
        return ((const RttiInstance<Node>*)rtti())->clone(this);
    }

    void Node::visit(struct Visitor& visitor) {}

    std::list<std::unique_ptr<Node>> NodeHeap::FloatingNodes;

    void NodeHeap::Track(Node* node) {
        FloatingNodes.emplace_back(node);
    }

    void NodeHeap::Clear() {
        FloatingNodes.clear();
    }

    void Symbol::visit(Visitor& visitor) {
        Node::visit(visitor);
        visitor.visit(Type);
    }

    void Visitor::visit(struct TypeName& type) {
        visitType(type);
    }

    void Visitor::visit(NodeRef& ref) {
        if (!ref || Visited.contains(ref))
            return;
        Visited.insert(ref);
        enterNode(ref);
        visitNode(ref);
        ref->visit(*this);
        exitNode(ref);
    }

    void Visitor::visit(Node* node) {
        auto ref = NodeRef::Temp(node);
        visit(ref);
    }

} // namespace pepper::ast
