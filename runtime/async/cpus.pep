## Processor counts.

import "sys_posix";
import "sys_windows";

## Returns the number of logical processors the operating system can run
## threads on: every hardware thread, so a core with hyperthreading (SMT)
## counts two or more times.
##
## This is the upper bound on how many threads can run at the same moment,
## and a sensible default size for a pool of CPU-bound worker threads. Inside
## a virtual machine or container it counts the processors the guest sees.
##
## @returns the number of logical processors, at least 1
## @see physical_cpus
## @example
##     import async;
##
##     main(): int {
##         print(async.logical_cpus(), " logical processors\n");
##         return 0;
##     }
export logical_cpus(): ulong {
    var count = _async_sys_logical_cpus();
    return count == 0 ? 1 : count;
}

## Returns the number of physical processor cores: hardware threads that
## share a core through hyperthreading (SMT) count once.
##
## On Linux the count comes from the kernel's CPU topology
## (`/sys/devices/system/cpu`), on macOS from `hw.physicalcpu`, and on
## Windows from `GetLogicalProcessorInformationEx`. Inside a virtual machine
## the guest cannot see the host's hardware, so this counts the cores the
## hypervisor presents. Where the topology is not available, it returns
## `logical_cpus()`.
##
## @returns the number of physical cores, at least 1 and at most `logical_cpus()`
## @see logical_cpus
export physical_cpus(): ulong {
    var logical = logical_cpus();
    var count = _async_sys_physical_cpus();
    if (count == 0 || count > logical) {
        return logical;
    }
    return count;
}
