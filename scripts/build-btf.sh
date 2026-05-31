#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 <rpi4|rpi5>" >&2
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

target="$1"

case "$target" in
    rpi4)
        model="Raspberry Pi 4/400/CM4 64-bit"
        defconfig="bcm2711_defconfig"
        kernel_image="kernel8"
        ;;
    rpi5)
        model="Raspberry Pi 5/500/CM5 64-bit"
        defconfig="bcm2712_defconfig"
        kernel_image="kernel_2712"
        ;;
    *)
        usage
        exit 2
        ;;
esac

repo_url="${KERNEL_REPO_URL:-https://github.com/raspberrypi/linux}"
branch="${KERNEL_BRANCH:-}"
workdir="${WORKDIR:-$PWD/work}"
linux_dir="${LINUX_DIR:-$workdir/linux}"
build_root="${BUILD_ROOT:-$workdir/build}"
out_root="${OUT_DIR:-$PWD/dist}"
out_dir="$out_root/$target"
build_dir="$build_root/$target"
jobs="${JOBS:-$(nproc)}"
skip_build="${SKIP_BUILD:-0}"

mkdir -p "$workdir" "$build_dir" "$out_dir"

if [[ ! -d "$linux_dir/.git" ]]; then
    clone_args=(clone --depth=1)
    if [[ -n "$branch" ]]; then
        clone_args+=(--branch "$branch")
    fi
    clone_args+=("$repo_url" "$linux_dir")
    git "${clone_args[@]}"
fi

cd "$linux_dir"

commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short=12 HEAD)"
commit_date="$(git show -s --format=%cI HEAD)"
resolved_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$resolved_branch" == "HEAD" ]]; then
    resolved_branch="${branch:-default}"
fi

export ARCH=arm64
export KERNEL_CC="${KERNEL_CC:-clang}"
export HOSTCC="${HOSTCC:-cc}"
export LLVM="${LLVM:-1}"
export LLVM_IAS="${LLVM_IAS:-1}"
export KERNEL="$kernel_image"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-github-actions}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-raspberrypi-os-btf}"
export KDEB_COMPRESS=none

make_args=(
    O="$build_dir"
    CC="$KERNEL_CC"
    HOSTCC="$HOSTCC"
    LLVM="$LLVM"
    LLVM_IAS="$LLVM_IAS"
)

if [[ "$skip_build" != "1" ]]; then
    make "${make_args[@]}" mrproper
    make "${make_args[@]}" "$defconfig"

    scripts/config \
        --file "$build_dir/.config" \
        --enable DEBUG_INFO \
        --enable DEBUG_INFO_BTF \
        --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT

    make "${make_args[@]}" olddefconfig

    if ! grep -qx 'CONFIG_DEBUG_INFO_BTF=y' "$build_dir/.config"; then
        echo "CONFIG_DEBUG_INFO_BTF was not enabled after olddefconfig" >&2
        exit 1
    fi

    make "${make_args[@]}" "-j$jobs" Image
fi

vmlinux="$build_dir/vmlinux"

echo "vmlinux info:"
ls "$vmlinux"
file "$vmlinux"

if [[ ! -s "$vmlinux" ]]; then
    echo "vmlinux at ${vmlinux} was not produced" >&2
    exit 1
fi

section_headers="$(mktemp)"
trap 'rm -f "$section_headers"' EXIT
llvm-readelf -S "$vmlinux" > "$section_headers"

if ! grep -q ' \.BTF ' "$section_headers"; then
    echo "vmlinux at ${vmlinux} does not contain a .BTF section" >&2
    exit 1
fi

kernel_release="$(make "${make_args[@]}" -s kernelrelease)"
artifact_base="raspberrypi-linux-${short_commit}-${target}-${kernel_release}"
btf_file="$out_dir/${artifact_base}.btf"
btf_zst_file="${btf_file}.zst"
metadata_file="$out_dir/${artifact_base}.metadata.json"
sha_file="$out_dir/${artifact_base}.sha256"

llvm-objcopy --dump-section .BTF="$btf_file" "$vmlinux"
zstd -f --rm -19 "$btf_file" -o "$btf_zst_file"

jq -n \
    --arg schema_version "1" \
    --arg target "$target" \
    --arg model "$model" \
    --arg arch "$ARCH" \
    --arg kernel_repo "$repo_url" \
    --arg kernel_branch "$resolved_branch" \
    --arg kernel_commit "$commit" \
    --arg kernel_commit_date "$commit_date" \
    --arg kernel_release "$kernel_release" \
    --arg defconfig "$defconfig" \
    --arg kernel_image "$kernel_image" \
    --arg btf_file "$(basename "$btf_zst_file")" \
    --arg btf_sha256 "$(sha256sum "$btf_zst_file" | awk '{print $1}')" \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      schema_version: $schema_version,
      target: $target,
      model: $model,
      arch: $arch,
      kernel_repo: $kernel_repo,
      kernel_branch: $kernel_branch,
      kernel_commit: $kernel_commit,
      kernel_commit_date: $kernel_commit_date,
      kernel_release: $kernel_release,
      defconfig: $defconfig,
      kernel_image: $kernel_image,
      btf: {
        file: $btf_file,
        compression: "zstd",
        sha256: $btf_sha256
      },
      build: {
        system: "nix develop",
        arch: $arch,
        llvm: true,
        built_at: $built_at
      }
    }' > "$metadata_file"

(
    cd "$out_dir"
    sha256sum "$(basename "$btf_zst_file")" "$(basename "$metadata_file")" > "$(basename "$sha_file")"
)

echo "Wrote:"
echo "  $btf_zst_file"
echo "  $metadata_file"
echo "  $sha_file"
