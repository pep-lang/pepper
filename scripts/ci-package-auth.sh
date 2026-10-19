#!/usr/bin/env bash
# CI-only: lets git clone the private packages the Pepper tools depend on,
# each with its own read-only deploy key whose private half is a repository
# secret:
#
#   package                        used by          secret
#   pep-lang/pepper-llvm      tools/compiler   PEPPER_LLVM_DEPLOY_KEY (#656)
#   pep-lang/pepper-lsp       tools/pep-lsp    PEPPER_LSP_DEPLOY_KEY
#
# Source it in the step that runs the tools tests:
#
#   env:
#     PEPPER_LLVM_DEPLOY_KEY: ${{ secrets.PEPPER_LLVM_DEPLOY_KEY }}
#     PEPPER_LSP_DEPLOY_KEY: ${{ secrets.PEPPER_LSP_DEPLOY_KEY }}
#   run: |
#     source scripts/ci-package-auth.sh
#     bash scripts/pepper-tests.sh
#
# A deploy key opens only its own repository, yet GitHub accepts the first
# key ssh offers, so each package gets a host alias of its own
# (`pepper-llvm.github.com`) in an SSH config that offers only its key, and
# git rewrites the package's HTTPS URL to that alias. The keys and the
# config go to 0600 files under the job's temporary folder, removed when the
# step's shell exits, and git reaches them through GIT_CONFIG_* and
# GIT_SSH_COMMAND variables of this shell: nothing is written to a git or
# SSH config file in the home folder (the runners are self-hosted and keep
# it), and nothing to the log. A secret that is not set (a fork, or before
# it is added) is reported and its package left alone.

# Never trace the lines that handle the keys.
case $- in *x*) _package_auth_trace=1; set +x ;; *) _package_auth_trace= ;; esac

_package_auth_dir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
# Windows' RUNNER_TEMP is a D:\ path; Git Bash's ssh wants /d/.
command -v cygpath > /dev/null && _package_auth_dir=$(cygpath -u "$_package_auth_dir")
_package_auth_dir=$(mktemp -d "$_package_auth_dir/package-keys.XXXXXX")
trap 'rm -rf "'"$_package_auth_dir"'"' EXIT
# GitHub's published host key (https://docs.github.com/en/authentication/
# keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints), so
# the first connection trusts nothing it is shown.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$_package_auth_dir/known_hosts"
(umask 077 && : > "$_package_auth_dir/config")
_package_auth_count=0

# _package_auth <repository> <secret name>: routes the repository's clones
# through its deploy key, when the secret is set.
_package_auth() {
  local repository=$1 secret=$2
  local key=${!secret:-}
  if [ -z "$key" ]; then
    echo "::notice::$secret is not set, so git cannot clone the private $repository package and the tests that use it will fail to fetch it."
    return
  fi
  # A key pasted on Windows may carry CRLF line ends, which ssh rejects.
  (umask 077 && printf '%s\n' "$key" | tr -d '\r' > "$_package_auth_dir/$repository.key")
  cat >> "$_package_auth_dir/config" <<EOF
Host $repository.github.com
  HostName github.com
  User git
  IdentityFile $_package_auth_dir/$repository.key
  IdentitiesOnly yes
  UserKnownHostsFile $_package_auth_dir/known_hosts
  HostKeyAlias github.com
  StrictHostKeyChecking yes
EOF
  local index=${GIT_CONFIG_COUNT:-0}
  export "GIT_CONFIG_KEY_${index}=url.git@$repository.github.com:pep-lang/$repository.insteadOf"
  export "GIT_CONFIG_VALUE_${index}=https://github.com/pep-lang/$repository"
  export GIT_CONFIG_COUNT=$((index + 1))
  _package_auth_count=$((_package_auth_count + 1))
  echo "git clones $repository over SSH with $secret."
}

_package_auth pepper-llvm PEPPER_LLVM_DEPLOY_KEY
_package_auth pepper-lsp PEPPER_LSP_DEPLOY_KEY
if [ "$_package_auth_count" -gt 0 ]; then
  export GIT_SSH_COMMAND="ssh -F '$_package_auth_dir/config'"
fi
unset -f _package_auth
unset _package_auth_dir _package_auth_count

[ -n "$_package_auth_trace" ] && set -x
unset _package_auth_trace
