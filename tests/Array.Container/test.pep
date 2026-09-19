

main(): int {
    var nums = array<int>();
    nums.append(42);
    nums.append(12);
    nums[1] = 42;
    return nums[0] - nums[1];
}
