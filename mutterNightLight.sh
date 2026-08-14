#!/usr/bin/env bash
#
# Rebuild Fedora's mutter with the identical-monitor Night Light fix.
#
#   ./mutterNightLight.sh           # rebuild and install if Fedora shipped a new mutter
#   ./mutterNightLight.sh --check   # exit 0 = patched build is current, 1 = rebuild needed
#
# Why: two identical monitors are two MetaColorDevice objects that generate the
# same colord profile key. Upstream rejects the second request with "Profile
# generation already in progress", so that monitor ends up with no device
# profile, never runs update_white_point(), and its CRTC gets no gamma LUT —
# Night Light only tints one screen. patches/ carries the fix; this script
# re-applies it to whatever mutter version dnf currently offers, so a plain
# `dnf upgrade` replacing the patched build is repaired by re-running this.
#
# The build happens against the stock Fedora source RPM, so the result is the
# distro package plus one patch — nothing else changes. Built RPMs are kept in
# $BUILD_DIR/RPMS so they can be reinstalled or copied to another machine.
#
# Upstream tracking: https://gitlab.gnome.org/GNOME/mutter/-/issues/4736
# Drop this script once the fix lands in a Fedora mutter build — the version
# check below will keep rebuilding forever otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATCH="$SCRIPT_DIR/patches/0001-color-Coalesce-generated-device-profile-requests.patch"
BUILD_DIR="${MUTTER_NIGHTLIGHT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mutter-nightlight}"
# Release suffix that marks our builds and sorts above the stock package:
# 1.fc44.nightlight > 1.fc44, and the next Fedora release (2.fc44) still wins.
SUFFIX=nightlight

# What dnf would install, and what is installed now.
repo_evr() { dnf repoquery --latest-limit 1 --qf '%{version}-%{release}\n' "mutter.$(rpm -E %_arch)" 2>/dev/null | tail -1; }
installed_evr() { rpm -q --qf '%{version}-%{release}\n' mutter 2>/dev/null || true; }

TARGET_EVR="$(repo_evr).$SUFFIX"

# --check is for timers and hooks: answer, don't build.
if [[ ${1:-} == --check ]]; then
  if [[ $(installed_evr) == "$TARGET_EVR" ]]; then
    echo "mutter $TARGET_EVR is installed and current"
    exit 0
  fi
  echo "mutter $(installed_evr) installed, patched build should be $TARGET_EVR"
  exit 1
fi

source "$SCRIPT_DIR/log.sh"

step "Checking for a new mutter"
say "installed: $(installed_evr)"
say "wanted:    $TARGET_EVR"
[[ -f $PATCH ]] || { warn "missing $PATCH"; exit 1; }
if [[ $(installed_evr) == "$TARGET_EVR" ]]; then
  cached "patched mutter is already current"
  exit 0
fi

step "Installing build tooling"
run sudo dnf install -y rpm-build

step "Downloading the mutter source RPM"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{SOURCES,SPECS}
run dnf download --source --destdir "$BUILD_DIR" mutter
srpm=$(echo "$BUILD_DIR"/mutter-*.src.rpm)
[[ -f $srpm ]] || { warn "no source RPM downloaded"; exit 1; }
# Trust the source RPM over the repo query for what we are actually building.
TARGET_EVR="$(rpm -q --qf '%{version}-%{release}' -p "$srpm").$SUFFIX"
say "got $(basename "$srpm")"

step "Applying the Night Light patch to the spec"
( cd "$BUILD_DIR/SOURCES" && rpm2cpio "$srpm" | cpio -idm --quiet )
mv "$BUILD_DIR/SOURCES/mutter.spec" "$BUILD_DIR/SPECS/mutter.spec"
spec="$BUILD_DIR/SPECS/mutter.spec"
cp "$PATCH" "$BUILD_DIR/SOURCES/"

# %autosetup is what applies PatchN. If Fedora ever switches this spec back to a
# plain %setup, the patch would be silently ignored and we would ship an
# unpatched build labelled as patched.
grep -q '^%autosetup' "$spec" || { warn "spec no longer uses %autosetup — patch would be ignored"; exit 1; }

sed -i "/^Source0:/a Patch900:      $(basename "$PATCH")" "$spec"
sed -i "s/^Release:.*/Release:       ${TARGET_EVR#*-}/" "$spec"
say "building mutter-$TARGET_EVR"

step "Installing mutter's build dependencies"
run sudo dnf builddep -y "$srpm"

step "Building the patched RPMs"
log="$BUILD_DIR/build.log"
say "this takes several minutes; full output in $log"
# debug_package off: the debuginfo packages double the build time and nothing
# here needs them.
if ! rpmbuild --define "_topdir $BUILD_DIR" --define "debug_package %{nil}" \
     --clean -bb "$spec" > "$log" 2>&1; then
  warn "rpmbuild failed, last 40 lines:"
  tail -40 "$log" | while IFS= read -r l; do say "$l"; done
  exit 1
fi

# The patch removes this string. If it survived, the patch did not really apply
# to the code that ships, whatever rpmbuild said.
main_rpm=$(find "$BUILD_DIR/RPMS" -name "mutter-$TARGET_EVR.*.rpm" -print -quit)
[[ -n $main_rpm ]] || { warn "no mutter-$TARGET_EVR RPM was built"; exit 1; }
if rpm2cpio "$main_rpm" | grep -aq "Profile generation already in progress"; then
  warn "built libmutter still rejects concurrent profile requests — patch did not take"
  exit 1
fi
say "built $(basename "$main_rpm")"

step "Installing the patched RPMs"
# mutter-devel carries an exact-version dependency, so every installed
# subpackage has to move to the new build in one transaction.
rpms=()
while read -r name; do
  f=$(find "$BUILD_DIR/RPMS" -name "$name-$TARGET_EVR.*.rpm" -print -quit)
  [[ -n $f ]] || { warn "installed $name has no matching build"; exit 1; }
  rpms+=("$f")
done < <(rpm -qa --qf '%{name}\n' | grep -xE 'mutter|mutter-common|mutter-devel|mutter-tests|mutter-devkit')

run sudo dnf install -y "${rpms[@]}"
say "log out and back in to run the patched mutter"
