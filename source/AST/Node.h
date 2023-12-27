
#pragma once

#include <list>
#include <string>

#include "AST/TypeName.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/PointerIntPair.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"

#define AST_NODE_POD_CLONE(N)                                                                                          \
    inline Node* clone() const override {                                                                              \
        return static_cast<const RttiInstance<N>*>(rtti())->clone(this);                                               \
    }

namespace pepper::ast {

    struct Visitor;

    struct Node {
        DECLARE_RTTI(Node);

        SourceLocation Source;

        static void PushSource(const SourceLocation& source);
        static void PopSource();

        virtual ~Node();

        template <typename N>
        N* cloneAs() const {
            assert(is<N>() && "Cannot cloneAs on unrelated types");
            auto copy = clone();
            copy->Source = Source;
            return copy->as<N>();
        }

        virtual Node* clone() const;

        virtual void visit(struct Visitor& visitor);

        std::string source(int width = -1, int indent = 0, const char* sep = "") const;
        std::string nodeName() const;
        virtual std::string toString() const;
        virtual std::string dump(int indent = 0) const;

      protected:
        Node();

        static SourceLocation TokenSource;
        static Vector<SourceLocation> SourceStack;
    };

    template <typename N>
    concept TNode = std::is_base_of_v<Node, N>;

    // Nodes are stored in NodeRefs so they can be replaced by AST passes
    struct NodeRef {
        Node* Ref;
        bool Detached = false;

        NodeRef(Node* node = nullptr, bool temp = false) {
            Ref = node;
            Detached = temp;
        }

        NodeRef(const NodeRef& rhs) = delete;
        NodeRef(NodeRef&& rhs) = default;
        NodeRef& operator=(const NodeRef& rhs) = delete;

        NodeRef& operator=(Node* node) {
            reset(node);
            return *this;
        }

        const RTTI* rtti() const {
            assert(Ref);
            return Ref->rtti();
        }

        void reset(Node* node = nullptr) {
            assert(attached() && "Assignment to an unattached NodeRef is a no-op");
            if (node->Source.File.empty()) {
                if (Ref) {
                    node->Source = Ref->Source;
                }
            }

            Ref = node;
        }

        bool attached() const {
            return !Detached;
        }

        operator bool() const {
            return Ref != nullptr;
        }

        operator Node*() const {
            return Ref;
        }

        Node* operator->() const {
            return Ref;
        }

        Node* node() const {
            return Ref;
        }

        static NodeRef Temp(Node* node) {
            return NodeRef(node, true);
        }
    };

    template <TNode N>
    struct TNodeRef : public NodeRef {
        TNodeRef(N* node = nullptr, bool temp = false)
            : NodeRef(node, temp) {}

        TNodeRef(const TNodeRef& ref) {
            *this = ref;
        }

        TNodeRef(TNodeRef&&) noexcept = default;

        TNodeRef& operator=(const TNodeRef& rhs) {
            Ref = rhs.node() ? rhs.node()->template cloneAs<N>() : nullptr;
            return *this;
        }

        N* operator->() const {
            return static_cast<N*>(node());
        }

        N& operator*() const {
            return *static_cast<N*>(node());
        }

        operator N*() const {
            return static_cast<N*>(node());
        }

        N* node() const {
            return static_cast<N*>(NodeRef::node());
        }
    };

    // All nodes, when created, get inserted into the NodeHeap. Single and orphaned nodes remain in the NodeHeap,
    // and can be safely cleared after codegen.
    class NodeHeap {
      private:
        static std::list<std::unique_ptr<Node>> FloatingNodes;

      public:
        static void Track(Node* node);
        static void Clear();
    };

    template <TNode N>
    struct NodeList : Vector<TNodeRef<N>> {
        using base = Vector<TNodeRef<N>>;
        using Vector<TNodeRef<N>>::Vector;

        using iterator = typename base::iterator;
        using const_iterator = typename base::const_iterator;

        NodeList(std::initializer_list<N*> nodes) {
            for (auto n : nodes)
                push_back(n);
        }

        void insert(iterator it, N* node) {
            base::insert(it, TNodeRef{node});
        }

        void insert_after(const Node* insertNode, Node* newNode) {
            auto it = std::find(this->begin(), this->end(), insertNode);
            if (it != this->end()) {
                insert(it + 1, newNode);
            }
        }

        void insert_before(const Node* insertNode, Node* newNode) {
            auto it = std::find(this->begin(), this->end(), insertNode);
            if (it != this->end()) {
                insert(it, newNode);
            }
        }

        void push_back(N* node) {
            base::push_back(TNodeRef{node});
        }

        void clone(const NodeList& src) {
            base::clear();
            for (auto& link : src) {
                push_back(link->template cloneAs<N>());
            }
        }

        NodeList clone() const {
            NodeList cloned;
            for (auto& node : *this) {
                cloned.push_back(node->template cloneAs<N>());
            }
            return cloned;
        }

        // Just alias the merged nodes
        template <TNode T>
        void merge(const NodeList<T>& other) {
            for (const auto& n : other) {
                push_back(&*n);
            }
        }
    };

    // NOOP
    struct None : public Node {
        DECLARE_RTTI(None, Node);
        AST_NODE_POD_CLONE(None);
    };

    // Placeholder in the l-value stack for nodes that haven't been constructed yet, but need to be
    // in the stack to cause r-values to be collected
    struct Pending : public Node {
        DECLARE_RTTI(Pending, Node);

        const RTTI* Type;
        Node* Value;

        template <typename N>
        Pending(N* node = nullptr) {
            Value = node;
            Type = RTTI::of<N>();
        }

        template <typename N>
        static Pending* New(N* node = nullptr) {
            return new Pending(node);
        }
    };

    struct Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

        TypeName Type;
        Ident Name;
        bool Hidden = false;

      public:
        Symbol(const TypeName& type, const Ident& name, bool hidden = false)
            : Type(type)
            , Name(name)
            , Hidden(hidden) {}

        void visit(Visitor& visitor) override;
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        virtual const TypeName& type() const {
            static TypeName Auto("__auto");
            return Auto;
        }
    };

    using ExprList = NodeList<Expression>;

    class Import : public Node {
        DECLARE_RTTI(Import, Node);

        std::string Module;
        std::string Alias;
        bool Local;

      public:
        Import(const std::string& import, bool local = false, const Ident& alias = "")
            : Module(import)
            , Alias(alias)
            , Local(local) {}

        std::string toString() const override {
            return llvm::formatv("{0}: {1}{2}{1} {3}", nodeName(), Local ? "\"" : "", Module, Alias);
        }

        std::string dump(int) const override {
            return toString();
        }
    };

    struct ScopeTarget {
        Node* This;

        ScopeTarget(Node* thisNode)
            : This(thisNode) {}

        template <typename N>
        N* to() {
            return This->as<N>();
        }

        template <typename N>
        bool is() const {
            return This->is<N>();
        }

        virtual void addMethod(class MethodDecl* method) {
            assert(!"ScopeTarget does not accept MethodDecls");
        }

        virtual void addFunction(class FunctionDef* function) {
            assert(!"ScopeTarget does not accept Methods");
        }

        virtual void addVariable(class VariableDef* var) {
            assert(!"ScopeTarget does not accept fields");
        }
    };
} // namespace pepper::ast
