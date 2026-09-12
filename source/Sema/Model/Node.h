
#pragma once

#include <list>
#include <string>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "Sema/Model/TypeName.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/PointerIntPair.h"

#define SEMA_NODE_POD_CLONE(N)                                                                                         \
    inline Node* clone() const override {                                                                              \
        return static_cast<const RttiInstance<N>*>(rtti())->clone(this);                                               \
    }

namespace pepper::sema {

    struct Visitor;

    struct Node {
        DECLARE_RTTI(Node);

        SourceLocation source_loc;

        static SourceLocation get_source_location();
        static void push_source(const SourceLocation& source);
        static void pop_source();

        virtual ~Node();

        template <typename N>
        N* clone_as() const {
            assert(is<N>() && "Cannot clone_as on unrelated types");
            auto copy = clone();
            copy->source_loc = source_loc;
            return copy->as<N>();
        }

        virtual Node* clone() const;

        virtual void visit(struct Visitor& visitor);

        std::string source(int width = -1, int indent = 0, const char* sep = "") const;
        std::string node_name() const;
        virtual std::string to_string() const;
        virtual std::string dump(int indent = 0) const;

      protected:
        Node();

        static Vector<SourceLocation> SourceStack;
    };

    template <typename N>
    concept TNode = std::is_base_of_v<Node, N>;

    // Nodes are stored in NodeRefs to act as a layer of indirection so they can be replaced by Sema passes
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
            if (node->source_loc.file.empty()) {
                if (Ref) {
                    node->source_loc = Ref->source_loc;
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

        static NodeRef temp(Node* node) {
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
            Ref = rhs.node() ? rhs.node()->template clone_as<N>() : nullptr;
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
        static void track(Node* node);
        static void clear();
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
                push_back(link->template clone_as<N>());
            }
        }

        NodeList clone() const {
            NodeList cloned;
            for (auto& node : *this) {
                cloned.push_back(node->template clone_as<N>());
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
        SEMA_NODE_POD_CLONE(None);
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
        static Pending* create(N* node = nullptr) {
            return new Pending(node);
        }
    };

    struct Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

        TypeName type;
        Ident name;
        bool is_hidden = false;

        Symbol(const TypeName& type, const Ident& name, bool hidden = false)
            : type(type)
            , name(name)
            , is_hidden(hidden) {}

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
        Import(const std::string& import = "", bool local = false, const Ident& alias = "")
            : Module(import)
            , Alias(alias)
            , Local(local) {}

        std::string to_string() const override {
            return llvm::formatv("{0}: {1}{2}{1} {3}", node_name(), Local ? "\"" : "", Module, Alias);
        }

        std::string dump(int) const override {
            return to_string();
        }
    };

    struct ScopeTarget {
        virtual ~ScopeTarget() = default;
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

        virtual void add_method(class MethodDecl* method) {
            assert(!"ScopeTarget does not accept MethodDecls");
        }

        virtual void add_function(class FunctionDef* function) {
            assert(!"ScopeTarget does not accept Methods");
        }

        virtual void add_field(class VariableDef* var) {
            assert(!"ScopeTarget does not accept fields");
        }
    };
} // namespace pepper::sema
