# tebako-packages/hello

Feedstock for **GNU hello** — the template prover for the
[`tebako-packages`](https://github.com/tebako-packages/index) feedstock
model (one repo per package, release line per upstream version).

- `recipe.yml` — upstream source (url + sha256), link mode, platforms,
  declared executables, pinned factory-tool release.
- `tools/` — the build machine: `emit_matrix`, `build`, `boot_smoke`,
  `stage`, `publish` (see `docs/conventions.md` in the index repo).
- `manifests/payload.yaml` — spec-03 manifest template, filled by
  `tools/stage`.
- `.github/workflows/build-payload.yml` — recipe → matrix build →
  boot-smoke → release.

Local build (one leg):

```console
$ tools/build recipe.yml 2.12 aarch64-macos   # fetch+verify, make, pack
$ tools/boot_smoke out/aarch64-macos          # run hello from the image
$ tools/stage out/aarch64-macos aarch64-macos # dist/hello-2.12-*.tfs + manifest
```

Releases carry per-triplet payload images (`hello-<version>-<triplet>.tfs`),
manifests, `SHA256SUMS`, and the resolved `tpkg-registry.yaml`.
