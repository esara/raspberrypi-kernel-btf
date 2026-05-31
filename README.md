# Raspberry Pi OS kernel BTF

This repository builds detached BTF blobs for Raspberry Pi-provided kernels that do not ship `/sys/kernel/btf/vmlinux`.

The GitHub Actions workflow runs daily, shallow-clones `https://github.com/raspberrypi/linux`, builds the 64-bit Raspberry Pi 4 and Raspberry Pi 5 kernel configurations in a Nix development environment, extracts `.BTF` from `vmlinux`, and publishes a GitHub release named after the upstream kernel commit.

## Targets

| Target | Raspberry Pi model | Kernel defconfig | Kernel image name |
| --- | --- | --- | --- |
| `rpi4` | Raspberry Pi 4 / 400 / CM4 64-bit | `bcm2711_defconfig` | `kernel8` |
| `rpi5` | Raspberry Pi 5 / 500 / CM5 64-bit | `bcm2712_defconfig` | `kernel_2712` |

## Manual build

```sh
nix develop
./scripts/build-btf.sh rpi4
./scripts/build-btf.sh rpi5
```

Artifacts are written to `dist/<target>/`:

- `*.btf.zst`: zstd-compressed raw BTF data extracted from `vmlinux`.
- `*.metadata.json`: machine-readable metadata for matching the blob to a kernel source commit and target.
- `*.sha256`: checksums for both files.

The workflow can also be run manually with a specific Raspberry Pi kernel branch.
