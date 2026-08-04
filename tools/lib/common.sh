#!/usr/bin/env bash
# Shared helpers for feedstock tools (tebako-packages/hello).
# Sourced by tools/build, tools/boot_smoke, tools/stage, tools/publish.
# Hard rule (docs/conventions.md): every download is sha256-verified;
# there are no silent fallbacks — every helper fails loudly.

set -euo pipefail

# Map a recipe platform triplet to the infix used by the factory-tool
# release assets (tamatebako/libtfs releases ship mkdwarfs/tebakofs as
# <tool>-<infix>).
asset_infix() {
  case "$1" in
    x86_64-linux-gnu)  printf '%s' linux-gnu-x86_64 ;;
    aarch64-linux-gnu) printf '%s' linux-gnu-arm64 ;;
    aarch64-macos)     printf '%s' macos-arm64 ;;
    x86_64-macos)      printf '%s' macos-x86_64 ;;
    *) echo "asset_infix: unknown platform triplet '$1'" >&2; return 1 ;;
  esac
}

# The PE suffix a platform's executables carry on disk (in the staging
# tree, hence in the image and its manifest): windows-ucrt builds produce
# hello.exe where the recipe declares the canonical suffix-free path.
exe_suffix_for() {
  case "$1" in
    *-windows-ucrt) printf '%s' .exe ;;
    *)              : ;;
  esac
}

# pack_image PLATFORM TOOLSDIR ROOT IMAGE — pack ROOT as the payload IMAGE
# with the platform's imaging tool. Unix legs: the libtfs factory mkdwarfs
# (flag parity with the C++ oracle; --force: the stage repack overwrites
# the build image — the tfs CLI's built-in replace semantics). windows-ucrt
# legs: the Rust tfs CLI's in-process dwarfs-t Writer (the shipping
# implementation — the feedstock never shells to mkdwarfs there). Hard
# error on an unknown platform — no silent fallback.
pack_image() {
  case "$1" in
    *-windows-ucrt) "$2/tfs.exe" mkimage --format dwarfs "$3" --output "$4" ;;
    *-linux-gnu|*-macos) "$2/mkdwarfs" -i "$3" -o "$4" --no-progress --set-owner 0 --force ;;
    *) echo "pack_image: unknown platform triplet '$1'" >&2; return 1 ;;
  esac
}

# image_reader PLATFORM OUTDIR — echo the image-reader binary one built
# leg carries: the factory tebakofs on unix, the staged tfs.exe on
# windows-ucrt (subcommand parity: info/tree/extract -d).
image_reader() {
  case "$1" in
    *-windows-ucrt)       printf '%s' "$2/tools/tfs.exe" ;;
    *-linux-gnu|*-macos)  printf '%s' "$2/tools/tebakofs" ;;
    *) echo "image_reader: unknown platform triplet '$1'" >&2; return 1 ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# fetch URL DEST — plain download, no verification (internal).
fetch() {
  echo "fetch: $1" >&2
  curl -fSL --retry 3 --retry-delay 2 -o "$2" "$1"
}

# fetch_verified URL EXPECTED_SHA256 DEST — download + verify, else die.
fetch_verified() {
  fetch "$1" "$3"
  local got
  got="$(sha256_of "$3")"
  if [ "$got" != "$2" ]; then
    echo "SHA256 MISMATCH: $1" >&2
    echo "  expected: $2" >&2
    echo "  got:      $got" >&2
    return 1
  fi
  echo "verified: $3 (sha256 $got)" >&2
}

# download_tool TOOL TRIPLET DESTDIR REPO RELEASE
# Downloads <tool>-<infix> from the given GitHub release and verifies it
# against the release's own SHA256SUMS asset (fetched once per destdir).
download_tool() {
  local tool="$1" triplet="$2" destdir="$3" repo="$4" release="$5"
  local infix asset base sums expected
  infix="$(asset_infix "$triplet")"
  asset="${tool}-${infix}"
  base="https://github.com/${repo}/releases/download/${release}"
  sums="${destdir}/SHA256SUMS.${release}"
  mkdir -p "$destdir"
  if [ ! -f "$sums" ]; then
    fetch "${base}/SHA256SUMS" "$sums"
  fi
  expected="$(awk -v a="$asset" '$2 == a {print $1}' "$sums")"
  if [ -z "$expected" ]; then
    echo "download_tool: no sha256 for asset '$asset' in ${repo} ${release} SHA256SUMS" >&2
    return 1
  fi
  fetch_verified "${base}/${asset}" "$expected" "${destdir}/${tool}"
  chmod +x "${destdir}/${tool}"
}

# download_tfs_cli DESTDIR REPO RELEASE SHA256
# Downloads the tfs CLI windows asset (tfs-<version>-windows-ucrt64.exe)
# from the tamatebako/tebako release as tfs.exe. That release ships no
# SHA256SUMS asset, so the caller passes the digest pinned in the recipe
# (tools.windows.sha256) — the pin is the trust anchor.
download_tfs_cli() {
  local destdir="$1" repo="$2" release="$3" sha256="$4"
  local asset="tfs-${release#v}-windows-ucrt64.exe"
  mkdir -p "$destdir"
  fetch_verified "https://github.com/${repo}/releases/download/${release}/${asset}" \
    "$sha256" "${destdir}/tfs.exe"
  chmod +x "${destdir}/tfs.exe"
}
