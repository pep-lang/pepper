# Breadth-first search: a Deque is the queue of nodes to visit.
main(): int {
    # Each node's neighbors: 0 - 1 - 2 - 4 and 0 - 3 - 4.
    int[][] edges = [[1, 3], [0, 2], [1, 4], [0, 4], [2, 3]];
    int[] hops = [0, -1, -1, -1, -1];

    Deque<int> queue = [0];
    while (!queue.is_empty) {
        var node = queue.pop_front();
        for (var next in edges[node as ulong]) {
            if (hops[next as ulong] >= 0) {
                continue;
            }
            hops[next as ulong] = hops[node as ulong] + 1;
            queue.push_back(next);
        }
    }
    assert(hops[4] == 2, "two hops from node 0 to node 4");

    # Both ends work: a window of the last three readings.
    var window = Deque<int>();
    for (var reading in [4, 8, 15, 16, 23]) {
        window.push_back(reading);
        if (window.count > 3) {
            window.pop_front();
        }
    }
    assert(window.front() == 15 and window.back() == 23, "the last three");
    assert(window[1] == 16, "indexed from the front");
    return 0;
}
