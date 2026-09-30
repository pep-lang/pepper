import async;

# The id of the request the running task is handling.
const request_id = async.TaskLocal<long>();

# Deep in the call chain, without the id passed down as a parameter.
current_request(): long {
    return request_id.get();
}

main(): int {
    # One worker: the three tasks take turns on one thread, so a
    # ThreadLocal could not tell them apart.
    async.run_with(
        async.RuntimeOptions().workers(1),
        () => {
            var tasks = Array<async.Task<bool>>();
            for (var id in [1, 2, 3]) {
                tasks.append(
                    async.Task<bool>.spawn_local(
                        () => {
                            request_id.set(id);
                            async.yield_now();  # the other tasks set their ids meanwhile
                            return current_request() == id;
                        }
                    )
                );
            }
            for (var task in tasks) {
                assert(task.join().value(), "each task sees its own id");
            }
            # This task never set one.
            assert(!request_id.is_set(), "a task starts with no value");
        }
    );
    return 0;
}
