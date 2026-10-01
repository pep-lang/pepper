import os;

main(): int {
    print($"{os.system_name()} {os.system_version()} on {os.architecture()}");
    print($"host {os.hostname()}: {os.logical_cpus()} logical processors, {os.physical_cpus()} cores");
    print($"{os.total_memory() / 1048576} MiB of memory in {os.page_size()}-byte pages");

    var user = os.user_name().value_or("unknown");
    var home = os.home_directory();
    print($"user {user}, home {home.is_some() ? home.value().to_string() : "unknown"}");
    print($"temporary files go in {os.temp_directory()}");

    var executable = os.system_os() == os.OperatingSystem.Windows ? "tool.exe" : "tool";
    assert(executable.starts_with("tool"), "picked a name");
    return 0;
}
