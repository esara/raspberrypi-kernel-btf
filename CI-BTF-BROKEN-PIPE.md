# CI BTF Broken Pipe Failure

## Symptom

GitHub Actions sometimes fails after building `vmlinux` with output like:

```text
vmlinux info:
/home/runner/work/raspberrypi-kernel-btf/raspberrypi-kernel-btf/work/build/rpi4/vmlinux
/home/runner/work/raspberrypi-kernel-btf/raspberrypi-kernel-btf/work/build/rpi4/vmlinux: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), statically linked, BuildID[sha1]=..., with debug_info, not stripped
LLVM ERROR: IO failure on output stream: Broken pipe
vmlinux at /home/runner/work/raspberrypi-kernel-btf/raspberrypi-kernel-btf/work/build/rpi4/vmlinux does not contain a .BTF section
```

It may affect only one matrix target, or both.

## Root Cause

This was a false negative in the validation command:

```sh
llvm-readelf -S "$vmlinux" | grep -q ' \.BTF '
```

The script runs with `set -o pipefail`. When `grep -q` finds `.BTF`, it exits immediately and closes its input pipe. `llvm-readelf` may still be writing section-header output at that point, so it can receive `SIGPIPE` and print:

```text
LLVM ERROR: IO failure on output stream: Broken pipe
```

Because `pipefail` is enabled, the non-zero status from `llvm-readelf` makes the whole pipeline fail even though `grep` already found `.BTF`. The script then incorrectly reports that `vmlinux` does not contain a `.BTF` section.

The intermittent behavior comes from output buffering and timing. A small change in scheduling can decide whether `llvm-readelf` finishes before or after `grep -q` closes the pipe.

## Fix

Avoid piping a long-running producer into `grep -q` under `pipefail`. Capture the full `llvm-readelf` output first, then grep the completed file:

```sh
section_headers="$(mktemp)"
trap 'rm -f "$section_headers"' EXIT
llvm-readelf -S "$vmlinux" > "$section_headers"

if ! grep -q ' \.BTF ' "$section_headers"; then
    echo "vmlinux at ${vmlinux} does not contain a .BTF section" >&2
    exit 1
fi
```

The script also now checks after `olddefconfig` that the kernel config really contains:

```text
CONFIG_DEBUG_INFO_BTF=y
```

That makes real configuration failures fail earlier with a clearer error.

## Verification

The generated configs for the current Raspberry Pi default branch keep BTF enabled for both targets:

```text
CONFIG_PAHOLE_VERSION=131
CONFIG_BPF_SYSCALL=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_DEBUG_INFO_BTF_MODULES=y
```

So the reported CI failure was not caused by the kernel build omitting BTF. It was caused by the validation pipeline.
