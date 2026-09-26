#!/usr/bin/env bash
# Shared helpers for feedstock tools (tebako-packages/hello).
# Sourced by tools/build, tools/boot_smoke, tools/stage, tools/publish.
# Hard rule (docs/conventions.md): every download is sha256-verified;
# there are no silent fallbacks — every helper fails loudly.

set -euo pipefail

# Map a recipe platform triplet to the infix used by the toolchain
# release assets (tamatebako/tebako releases ship the tfs CLI as
# tfs-<version>-<infix>[.exe]).
asset_infix() {
  case "$1" in
    x86_64-linux-gnu)    printf '%s' linux-gnu-x86_64 ;;
    aarch64-linux-gnu)   printf '%s' linux-gnu-arm64 ;;
    aarch64-macos)       printf '%s' macos-arm64 ;;
    x86_64-macos)        printf '%s' macos-x86_64 ;;
    x86_64-windows-ucrt) printf '%s' windows-ucrt64 ;;
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

# tfs_bin TOOLSDIR — the leg's verified tfs CLI (tfs.exe on windows-ucrt).
tfs_bin() {
  if [ -f "$1/tfs.exe" ]; then printf '%s' "$1/tfs.exe"; else printf '%s' "$1/tfs"; fi
}

# pack_image PLATFORM TOOLSDIR ROOT IMAGE — pack ROOT as the payload IMAGE
# with the leg's verified tfs CLI: `tfs mkimage --format limnifs` (the
# product's in-process writer; limnifs is the default tebako image
# format). Hard error on an unknown platform — no silent fallback.
pack_image() {
  case "$1" in
    *-windows-ucrt|*-linux-gnu|*-macos) "$(tfs_bin "$2")" mkimage --format limnifs "$3" --output "$4" ;;
    *) echo "pack_image: unknown platform triplet '$1'" >&2; return 1 ;;
  esac
}

# image_reader PLATFORM OUTDIR — echo the image-reader binary one built
# leg carries: the same verified tfs CLI on every platform (subcommand
# parity: info/tree/cat/stat/extract -d).
image_reader() {
  case "$1" in
    *-windows-ucrt|*-linux-gnu|*-macos)  tfs_bin "$2/tools" ;;
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

# download_tfs DESTDIR REPO RELEASE TRIPLET EXPECTED_SHA256
# Downloads tfs-<version>-<infix>[.exe] from the tamatebako/tebako
# release as tfs[.exe]. The recipe pin (tools.sha256.<infix>) is the
# trust anchor AND is cross-checked against the release's own SHA256SUMS
# (both anchored — the same rule the workflow pin checks follow).
download_tfs() {
  local destdir="$1" repo="$2" release="$3" triplet="$4" want="$5"
  local infix asset base sums got exe
  infix="$(asset_infix "$triplet")"
  exe=""; case "$triplet" in *-windows-ucrt) exe=".exe" ;; esac
  asset="tfs-${release#v}-${infix}${exe}"
  base="https://github.com/${repo}/releases/download/${release}"
  sums="${destdir}/SHA256SUMS.${release}"
  mkdir -p "$destdir"
  if [ ! -f "$sums" ]; then
    fetch "${base}/SHA256SUMS" "$sums"
  fi
  got="$(awk -v a="$asset" '$2 == a {print $1}' "$sums")"
  if [ "$got" != "$want" ]; then
    echo "download_tfs: pin mismatch for $asset: recipe=$want release=${got:-ABSENT}" >&2
    return 1
  fi
  fetch_verified "${base}/${asset}" "$want" "${destdir}/tfs${exe}"
  chmod +x "${destdir}/tfs${exe}"
}

# download_signer DESTDIR REPO RELEASE SHA256
# Downloads tebako-pkg-<version>-linux-gnu-x86_64 from the tamatebako/tebako
# release as tebako-pkg (the signer for the publish job, which always runs
# on ubuntu-24.04). The asset name carries the version, so — like
# download_tfs_cli — the digest pinned in the recipe (signing.tool.sha256)
# is the trust anchor.
download_signer() {
  local destdir="$1" repo="$2" release="$3" sha256="$4"
  local asset="tebako-pkg-${release#v}-linux-gnu-x86_64"
  mkdir -p "$destdir"
  fetch_verified "https://github.com/${repo}/releases/download/${release}/${asset}" \
    "$sha256" "${destdir}/tebako-pkg"
  chmod +x "${destdir}/tebako-pkg"
}
