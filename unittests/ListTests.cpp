
#include "Core/PolyIList.h"
#include "gtest/gtest.h"

using namespace pepper;

struct Node : public poly_ilist_node<Node> {
    int Value = 0;

    static int Created;
    static int Deleted;

    Node(int val)
        : Value(val) {
        ++Created;
    }

    ~Node() {
        ++Deleted;
    }

    bool operator==(int rhs) const {
        return Value == rhs;
    }

    bool operator!=(int rhs) const {
        return Value != rhs;
    }
};

int Node::Created = 0;
int Node::Deleted = 0;

TEST(List, Basic) {
    poly_ilist<Node> list = {
        new Node(1),
        new Node(2),
        new Node(3),
    };
    EXPECT_FALSE(list.empty());
    EXPECT_EQ(3, list.size());
    auto it = list.begin();
    EXPECT_EQ(1, *it++);
    EXPECT_EQ(2, *it++);
    EXPECT_EQ(3, *it++);
    EXPECT_EQ(list.end(), it);
    EXPECT_EQ(3, Node::Created);
    list.clear();
    EXPECT_EQ(3, Node::Deleted);
    EXPECT_EQ(0, list.size());
    EXPECT_TRUE(list.empty());
}

TEST(List, Destruct) {
    EXPECT_EQ(0, Node::Created);
    EXPECT_EQ(0, Node::Deleted);
    {
        poly_ilist<Node> list = {
            new Node(1),
            new Node(2),
            new Node(3),
        };
        EXPECT_EQ(3, list.size());
    }

    EXPECT_EQ(3, Node::Created);
    EXPECT_EQ(3, Node::Deleted);
}

TEST(List, PushBack) {
    poly_ilist<Node> list;
    EXPECT_TRUE(list.empty());
    list.push_back(*new Node(1));
    list.push_back(*new Node(2));
    list.push_back(*new Node(3));
    EXPECT_EQ(3, list.size());
    auto it = list.begin();
    EXPECT_EQ(1, *it++);
    EXPECT_EQ(2, *it++);
    EXPECT_EQ(3, *it++);
    EXPECT_EQ(list.end(), it);
    list.clear();
    EXPECT_EQ(0, list.size());
}

TEST(List, PushFront) {
    poly_ilist<Node> list;
    list.push_front(*new Node(1));
    list.push_front(*new Node(2));
    list.push_front(*new Node(3));
    EXPECT_EQ(3, list.size());
    auto it = list.begin();
    EXPECT_EQ(3, *it++);
    EXPECT_EQ(2, *it++);
    EXPECT_EQ(1, *it++);
    EXPECT_EQ(list.end(), it);
    list.clear();
    EXPECT_EQ(0, list.size());
}

TEST(List, AppendTransfer) {
    poly_ilist<Node> listA = {
        new Node(1),
        new Node(2),
        new Node(3),
    };
    poly_ilist<Node> listB;
    EXPECT_EQ(0, listB.size());
    listB.append(listA);
    EXPECT_EQ(0, listA.size());
    EXPECT_EQ(3, listB.size());
}
