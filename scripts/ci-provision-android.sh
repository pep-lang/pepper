#!/usr/bin/env bash
# CI-only: an Android emulator for scripts/mobile-test.sh on a GitHub-hosted
# Linux runner, whose image has the Android SDK, an NDK and KVM.
#
#   bash scripts/ci-provision-android.sh [<api-level>]
#
# Lets the runner's user open /dev/kvm, installs the emulator and the x86_64
# system image of <api-level> (default 34: Android 14, whose trusted roots
# are the Conscrypt module's), and creates the AVD `pepper` from it, which
# mobile-test.sh starts. An Apple silicon Mac runner cannot run the
# emulator (no nested virtualization), so the Android run goes here.
set -euo pipefail

api=${1:-34}
image="system-images;android-$api;default;x86_64"
tools="$ANDROID_HOME/cmdline-tools/latest/bin"

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
  | sudo tee /etc/udev/rules.d/99-kvm4all.rules > /dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

"$tools/sdkmanager" --install emulator platform-tools "$image"
echo no | "$tools/avdmanager" create avd --name pepper --package "$image" --force
"$ANDROID_HOME/emulator/emulator" -list-avds
