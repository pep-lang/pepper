# WASI (WebAssembly) fibers for the task runtime in task.pep: the same
# `_async_fiber_*` functions as fiber_posix.pep and fiber_windows.pep, each
# with [Target(OS(Wasi))]. WebAssembly cannot switch stacks (that needs the
# stack-switching proposal), so a task cannot run: creating its fiber
# panics. The thread's own context and the keys work as elsewhere.

import "sys_wasi";

[Target(OS(Wasi))]
_async_fiber_thread_context(): __ptr<void> {
    return _pep_malloc(24);
}

[Target(OS(Wasi))]
_async_fiber_release_thread_context(context: __ptr<void>) {
    _pep_free(context);
}

[Target(OS(Wasi))]
_async_fiber_create(stack_size: ulong, entry: __ptr<void>): __ptr<void> {
    panic("async: tasks are not supported on WASI, which cannot switch stacks");
    return __null;
}

[Target(OS(Wasi))]
_async_fiber_destroy(context: __ptr<void>) {
    _pep_free(context);
}

[Target(OS(Wasi))]
_async_fiber_switch(from: __ptr<void>, to: __ptr<void>) {
    panic("async: tasks are not supported on WASI, which cannot switch stacks");
}

[Target(OS(Wasi))]
_async_fiber_key_create(): ulong {
    return _async_sys_key_create(__null);
}

[Target(OS(Wasi))]
_async_fiber_key_get(key: ulong): __ptr<void> {
    return _async_sys_key_get(key);
}

[Target(OS(Wasi))]
_async_fiber_key_set(key: ulong, value: __ptr<void>) {
    _async_sys_key_set(key, value);
}
