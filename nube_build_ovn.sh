#!/usr/bin/env bash
# rules_foreign_cc build driver for the OVN/OVS fork (ozouai/ovn, OVN+OVS 25.03).
#
# WHY a custom driver instead of plain configure_make: OVN's build is coupled to
# OVS's *build tree* -- it links the .la archives inside ovs/lib + ovs/ovsdb,
# includes both ovs source and build dirs, and imports ovs/python at build time
# (see ovn/acinclude.m4 OVN_CHECK_OVS, ovn/Makefile.am). So OVS and OVN must build
# in ONE sandbox with OVS built *in source* (source==build), exactly as the legacy
# test-harness/images/build-ovn-fork.sh did. We reproduce that here.
#
# rules_foreign_cc invokes this as the "configure" step (configure_command) with
#   --prefix=$BUILD_TMPDIR/$INSTALL_PREFIX  as an argument, and runs no `make`
# afterwards (the BUILD sets targets=[]). We do boot+configure+make+install for
# both projects into PREFIX; rules_foreign_cc then collects PREFIX/{bin,lib,share}.
#
# CC/CFLAGS/LDFLAGS are exported by rules_foreign_cc before we run, so the two
# ./configure invocations inherit the Bazel C/C++ toolchain (incl. any --sysroot
# for cross-glibc targeting). We deliberately do NOT hardcode a compiler here.
set -euo pipefail

PREFIX=""
for arg in "$@"; do
  case "$arg" in
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
  esac
done
[ -n "$PREFIX" ] || { echo "nube_build_ovn.sh: no --prefix= in args: $*" >&2; exit 1; }

JOBS="$(nproc 2>/dev/null || echo 2)"
SRC="$(cd "$(dirname "$0")" && pwd)"   # == $BUILD_TMPDIR (the copied ovn tree)

[ -f "$SRC/ovs/configure.ac" ] || { echo "nube_build_ovn.sh: ovs/ submodule missing at $SRC/ovs" >&2; exit 1; }

echo "== [1/2] OVS (in-source build) -> $PREFIX  (-j$JOBS) =="
cd "$SRC/ovs"
./boot.sh
./configure --prefix="$PREFIX" --disable-ssl
make -j"$JOBS"
make install

echo "== [2/2] OVN against the OVS source tree -> $PREFIX  (-j$JOBS) =="
cd "$SRC"
./boot.sh
./configure --prefix="$PREFIX" --with-ovs-source="$SRC/ovs" --disable-ssl
make -j"$JOBS"
make install

echo "== OVN fork build complete =="
"$PREFIX/bin/ovn-northd" --version 2>/dev/null | head -1 || true
