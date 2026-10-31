<!-- Generated from runtime/async/cpus.pep by `pep-doc reference`. Do not edit. -->

# Processor counts

Processor counts.

Source: `runtime/async/cpus.pep`

## logical_cpus

```pepper
logical_cpus(): ulong
```

Returns the number of logical processors the operating system can run
threads on: every hardware thread, so a core with hyperthreading (SMT)
counts two or more times.

This is the upper bound on how many threads can run at the same moment,
and a sensible default size for a pool of CPU-bound worker threads. Inside
a virtual machine it counts the processors the guest sees. On Linux, a
CPU quota on the process's cgroup or any cgroup above it (cgroup v2's
`cpu.max`, or v1's `cpu.cfs_quota_us` over `cpu.cfs_period_us`, as
`docker run --cpus` sets) caps the count, rounded up to whole processors,
as Go and the JVM do: a quota of 1.5 processors counts as 2.

**Returns**
- the number of logical processors, at least 1

**See also**
- `physical_cpus`

**Example**
```pepper
import async;

main(): int {
    print($"{async.logical_cpus()} logical processors");
    return 0;
}
```

## physical_cpus

```pepper
physical_cpus(): ulong
```

Returns the number of physical processor cores: hardware threads that
share a core through hyperthreading (SMT) count once.

On Linux the count comes from the kernel's CPU topology
(`/sys/devices/system/cpu`), on macOS from `hw.physicalcpu`, and on
Windows from `GetLogicalProcessorInformationEx`. Inside a virtual machine
the guest cannot see the host's hardware, so this counts the cores the
hypervisor presents. Where the topology is not available, it returns
`logical_cpus()`.

**Returns**
- the number of physical cores, at least 1 and at most `logical_cpus()`

**See also**
- `logical_cpus`
