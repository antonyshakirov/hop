# Source at the entry point's top level so the EXIT trap follows the whole build.
HOP_BUILD_SCRATCH=$(/usr/bin/mktemp -d /private/tmp/hop-build.XXXXXXXX) || return
trap '
    hop_build_status=$?
    trap - EXIT
    /bin/rm -rf -- "$HOP_BUILD_SCRATCH" || hop_build_status=1
    exit "$hop_build_status"
' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export CLANG_MODULE_CACHE_PATH="$HOP_BUILD_SCRATCH/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$HOP_BUILD_SCRATCH/swift-module-cache"
