#!/usr/bin/env bash
# CI-only: lets git clone the private justinboswell/pepper-llvm package that
# tools/compiler depends on (#656), with the read-only deploy key whose
# private half is the repository secret PEPPER_LLVM_DEPLOY_KEY. Source it in
# the step that runs the tools tests:
#
#   env:
#     PEPPER_LLVM_DEPLOY_KEY: ${{ secrets.PEPPER_LLVM_DEPLOY_KEY }}
#   run: |
#     source scripts/ci-pepper-llvm-auth.sh
#     bash scripts/pepper-tests.sh
#
# The key goes to a 0600 file under the job's temporary folder, removed when
# the step's shell exits, and git reaches pepper-llvm over SSH with only that
# key, through GIT_CONFIG_* and GIT_SSH_COMMAND variables of this shell:
# nothing is written to a git or SSH config file (the runners are
# self-hosted and keep their home folder), and nothing to the log. Without
# the secret (a fork, or before it is added) it says so and changes nothing.

# Never trace the lines that handle the key.
case $- in *x*) _pepper_llvm_trace=1; set +x ;; *) _pepper_llvm_trace= ;; esac

if [ -z "${PEPPER_LLVM_DEPLOY_KEY:-}" ]; then
  echo "::notice::PEPPER_LLVM_DEPLOY_KEY is not set, so git cannot clone the private pepper-llvm package and the tools/compiler tests will fail to fetch it."
else
  _pepper_llvm_dir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
  # Windows' RUNNER_TEMP is a D:\ path; Git Bash's ssh wants /d/.
  command -v cygpath > /dev/null && _pepper_llvm_dir=$(cygpath -u "$_pepper_llvm_dir")
  _pepper_llvm_dir=$(mktemp -d "$_pepper_llvm_dir/pepper-llvm-key.XXXXXX")
  # A key pasted on Windows may carry CRLF line ends, which ssh rejects.
  (umask 077 && printf '%s\n' "$PEPPER_LLVM_DEPLOY_KEY" | tr -d '\r' > "$_pepper_llvm_dir/key")
  # GitHub's published host key (https://docs.github.com/en/authentication/
  # keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints), so
  # the first connection trusts nothing it is shown.
  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$_pepper_llvm_dir/known_hosts"
  trap 'rm -rf "'"$_pepper_llvm_dir"'"' EXIT
  export GIT_SSH_COMMAND="ssh -i '$_pepper_llvm_dir/key' -o IdentitiesOnly=yes -o UserKnownHostsFile='$_pepper_llvm_dir/known_hosts' -o StrictHostKeyChecking=yes"
  _pepper_llvm_index=${GIT_CONFIG_COUNT:-0}
  export "GIT_CONFIG_KEY_${_pepper_llvm_index}=url.git@github.com:justinboswell/pepper-llvm.insteadOf"
  export "GIT_CONFIG_VALUE_${_pepper_llvm_index}=https://github.com/justinboswell/pepper-llvm"
  export GIT_CONFIG_COUNT=$((_pepper_llvm_index + 1))
  unset _pepper_llvm_dir _pepper_llvm_index
  echo "git clones pepper-llvm over SSH with PEPPER_LLVM_DEPLOY_KEY."
fi

[ -n "$_pepper_llvm_trace" ] && set -x
unset _pepper_llvm_trace
