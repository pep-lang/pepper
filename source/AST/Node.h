
#pragma once

#include <list>
#include <string>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/PolyIList.h"
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

    struct TypeName {
        enum TypeFlags {
            Scalar = 0,
            Array = 1,
            Function = 2,
        } Flags;

        Ident Name;
        std::vector<TypeName> SubTypes;

        TypeName(const Ident& name = {}, const Vector<TypeName, 0>& types = {}, TypeFlags flags = Scalar)
            : Flags(flags)
            , Name(name)
            , SubTypes(types.begin(), types.end()) {}

        TypeName(const TypeName&) = default;
        TypeName(TypeName&&) = default;
        TypeName& operator=(const TypeName&) = default;

        bool empty() const {
            return Name.empty() && SubTypes.empty();
        }

        operator std::string() const {
            return toString();
        }

        bool operator==(const TypeName& rhs) const {
            return Flags == rhs.Flags && Name == rhs.Name && SubTypes == rhs.SubTypes;
        }

        bool operator!=(const TypeName& rhs) const {
            return !(*this == rhs);
        }

        bool isScalar() const {
            return Flags == Scalar;
        }

        bool isArray() const {
            return Flags == Array;
        }

        bool isFunction() const {
            return Flags == Function;
        }

        bool isGeneric() const {
            return (Flags != Array && !SubTypes.empty());
        }

        bool isStruct() const;
        bool isIntegral() const;
        bool isPointer() const;

        const TypeName& elementType() const {
            assert(Flags == Array);
            assert(SubTypes.empty());
            return *this;
        }

        std::string toString() const;

        static TypeName MakeArray(const Ident& arrayTypeName, const TypeName& elementType) {
            return {arrayTypeName, {elementType}, Array};
        }

        static TypeName MakeStruct(const Ident& structTypeName, const Vector<TypeName>& subTypes = {}) {
            return {structTypeName, subTypes};
        }

        static TypeName MakeFunction(const Ident& name, const Vector<TypeName>& genericArgs = {}) {
            return {name, genericArgs, Function};
        }

        static const TypeName& Widest(const TypeName& lhs, const TypeName& rhs);

        static const TypeName Void;
        static const TypeName Auto;
        static const TypeName Bool;

        static const TypeName VoidPtr;
        static const TypeName Int8;
        static const TypeName UInt8;
        static const TypeName Int32;
        static const TypeName UInt32;
        static const TypeName Int64;
        static const TypeName UInt64;
        static const TypeName Double;
        static const TypeName Float;

        static llvm::StringSet<> IntegralTypes;
    };

    struct Node {
        DECLARE_RTTI(Node);

        static SourceLocation TokenSource;
        SourceLocation Source;

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
        virtual std::string toString() const;
        virtual std::string dump(int indent = 0) const;

      protected:
        Node();
    };

    template <typename N>
    concept TNode = std::is_base_of_v<Node, N>;

    // Nodes are stored in NodeRefs so they can be replaced by AST passes
    struct NodeRef {
        llvm::PointerIntPair<Node*, 1, bool> Ref;

        NodeRef(Node* node = nullptr, bool temp = false) {
            Ref.setPointerAndInt(node, temp);
        }

        NodeRef(const NodeRef& rhs) = delete;
        NodeRef(NodeRef&& rhs) = default;
        NodeRef& operator=(const NodeRef& rhs) = delete;

        NodeRef& operator=(Node* node) {
            reset(node);
            return *this;
        }

        const RTTI* rtti() const {
            assert(Ref.getPointer());
            return Ref.getPointer()->rtti();
        }

        void reset(Node* node = nullptr) {
            assert(attached() && "Assignment to an unattached NodeLink is a no-op");
            Ref.setPointer(node);
        }

        bool attached() const {
            return !Ref.getInt();
        }

        operator bool() const {
            return Ref.getPointer() != nullptr;
        }

        operator Node*() const {
            return Ref.getPointer();
        }

        Node* operator->() const {
            return Ref.getPointer();
        }

        Node* node() const {
            return Ref.getPointer();
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
            Ref.initWithPointer(rhs.node() ? rhs.node()->template cloneAs<N>() : nullptr);
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
    struct NodeList : public Vector<TNodeRef<N>> {
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

        void push_back(N* node) {
            base::push_back(TNodeRef{node});
        }

        void clone(const NodeList& src) {
            base::clear();
            for (auto& link : src) {
                push_back(link->template cloneAs<N>());
            }
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

    template <typename T>
    class Resolvable;

    class Visitor {
        llvm::DenseSet<Node*> Visited;

      protected:
        virtual void visitType(struct TypeName& type) {}

        virtual void enterNode(NodeRef& node) {}

        virtual void visitNode(NodeRef& node) {}

        virtual void exitNode(NodeRef& node) {}

      public:
        void visit(struct TypeName& type);

        void visit(NodeRef& ref);

        void visit(Node* node);

        template <typename T>
        void visit(Resolvable<T>& target);
    };

    template <typename T>
    class Resolvable {
        friend class Visitor;

        TypeName Target;
        T* Value = nullptr;

      public:
        Resolvable(const TypeName& name = {})
            : Target(name)
            , Value(nullptr) {
            Instances().insert(this);
        }

        explicit Resolvable(T* value)
            : Value(value)
            , Target(value->Name) {}

        Resolvable(const Resolvable& rhs) {
            Instances().insert(this);
            *this = rhs;
        }

        Resolvable(Resolvable&& rhs) noexcept {
            Instances().insert(this);
            std::swap(*this, rhs);
        }

        ~Resolvable() {
            Instances().erase(this);
        }

        Resolvable& operator=(const Resolvable& rhs) {
            Target = rhs.Target;
            Value = rhs.Value;
            return *this;
        }

        Resolvable& operator=(T* value) {
            Value = value;
            Target = value->Name;
            return *this;
        }

        Resolvable& operator=(const TypeName& name) {
            assert(!Value && "Attempted to overwrite already resolved Resolvable with name");
            Target = name;
            return *this;
        }

        const std::string name() const {
            return (Value) ? Value->Name : Target;
        }

        T* value() const {
            return Value;
        }

        const TypeName& target() const {
            return Target;
        }

        void resolve(T* val) {
            Value = val;
        }

        const std::string toString() const {
            return Target.toString();
        }

        operator bool() const {
            return !Target.empty() || !!Value;
        }

        operator TypeName() const {
            return Target;
        };

        operator T*() const {
            return Value;
        }

        T* operator->() const {
            assert(Value && "Value is not resolved yet");
            return Value;
        }

        void visit(Visitor& visitor) {
            visitor.visit(Target);
        }

        static llvm::DenseSet<Resolvable*>& Instances() {
            static llvm::DenseSet<Resolvable*> instances;
            return instances;
        }
    };

    template <typename T>
    inline void Visitor::visit(Resolvable<T>& target) {
        visit(target.Target);
    }

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

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Type);
        }
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
            return llvm::formatv("{0} {1}{2}{1} {3}", Node::toString(), Local ? "\"" : "", Module, Alias);
        }

        std::string dump(int) const override {
            return toString();
        }
    };
} // namespace pepper::ast

namespace llvm {
    template <>
    struct DenseMapInfo<pepper::ast::TypeName> {
        static inline pepper::ast::TypeName getEmptyKey() {
            return pepper::ast::TypeName{"__EMPTY"};
        }

        static inline pepper::ast::TypeName getTombstoneKey() {
            return pepper::ast::TypeName{"__TOMBSTONE"};
        }

        static unsigned getHashValue(const pepper::ast::TypeName& Val) {
            return hash_value(Val.toString());
        }

        static bool isEqual(const pepper::ast::TypeName& LHS, const pepper::ast::TypeName& RHS) {
            return LHS == RHS;
        }
    };
} // namespace llvm
