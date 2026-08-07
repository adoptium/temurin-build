# Release Download & Validation

Scripts and Jenkins pipeline for validating Temurin release artifacts across all supported platforms.

---

## Contents

| File | Purpose |
|---|---|
| [`Jenkinsfile`](Jenkinsfile) | Multi-stage Jenkins pipeline — download, GPG/SBOM verify, parallel per-arch binary checks, summary |
| [`release_download_test_new.sh`](release_download_test_new.sh) | Core validation script — downloads release artifacts and runs all checks |
| [`validate_all_archs.sh`](validate_all_archs.sh) | Local helper — runs the validation script in parallel for all arch/os combinations |
| [`unit_tests/test_release_download.sh`](unit_tests/test_release_download.sh) | Unit tests for the pure-logic functions in `release_download_test_new.sh` |

---

## Pipeline: `Jenkinsfile`

### Overview

A three-stage Jenkins declarative pipeline that validates a complete Temurin release.

```
Stage 1 — Download, GPG Verify & SBOM Validation  (single 'worker' node)
Stage 2 — Binary Checks: <arch>                    (parallel, native agents per arch/os)
Stage 3 — Summary                                  (single 'worker' node)
```

### Stage 1 — Download, GPG Verify & SBOM Validation

Runs on a single central `worker` node. Performs two steps in sequence on the **same** node so the staging directory written by step 1a is available to step 1b:

- **Step 1a** (`-g -k`): Downloads the full release (or a filtered subset if `FILTER_ARCHS` is set), imports the Temurin GPG key, verifies every GPG signature and SHA256 checksum, and checks archive integrity. Keeps the staging directory for step 1b.
- **Step 1b** (`-c`): Validates all SBOM JSON files for every arch/os using the staging area from step 1a. Runs SBOM validation centrally to avoid `jq` PATH issues on exotic nodes (s390x, AIX) and glibc/musl incompatibility for the CycloneDX CLI on Alpine agents.

Per-platform result files written by both steps are stashed as `platform-central-results` for the arch-node stages and the Summary stage.

The full staging directory and GPG keyring are cleaned up in `post { always }` after stashing.

### Stage 2 — Binary Checks (parallel)

Runs one named stage per arch/os in parallel on the native Jenkins agent for that platform. Each stage:

1. Checks out the repo and unstashes `platform-central-results`.
2. Calls `release_download_test_new.sh -G -C` — downloads only the binaries for its own arch/os, skipping GPG (done centrally) and SBOM validation (done centrally).
3. Runs `java -version` natively and verifies GLIBC linkage and GCC compiler version via `strings`.
4. Windows stages run `java.exe -Xinternalversion` to verify the MSVC toolset version (VS 2022, toolset ≥ 1930) instead of POSIX `strings` checks.
5. Stashes the binary result file (`binary_*.result`) in a per-stage stash regardless of pass/fail, then calls `deleteDir()`.

Mac stages are wrapped in `retry(2)` to handle transient GHA runner provisioning failures.

Platforms not applicable for the requested JDK version (e.g. `arm/linux` for JDK ≥ 21) are skipped — the Summary stage renders a `SKIP-VER` row for them directly from `ARCH_STAGE_DEFS`.

### Stage 3 — Summary

Runs on a single `worker` node. Unstashes all result files, prints a cross-platform validation table to the build log, then cleans the workspace.

Example output:

```
===================================================================
 Validation Summary: jdk-21.0.12+8
===================================================================
Platform               | GPG      | Archive  | SBOM     | Binary   |
-------------------------------------------------------------------
x64/linux              | PASS     | PASS     | PASS     | PASS     |
aarch64/linux          | PASS     | PASS     | PASS     | PASS     |
...
arm/linux              | N/A      | N/A      | N/A      | SKIP-VER | (not released for JDK 21, valid range: 8–20)
...
-------------------------------------------------------------------
OVERALL: PASS
===================================================================
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `TAG` | _(required)_ | Release tag to validate, e.g. `jdk-21.0.3+9` or `jdk8u422-b05` |
| `VERBOSE` | `false` | Enable full per-file validation logging (`-v` flag) |
| `FILTER_ARCHS` | _(blank)_ | **Debug only.** Comma-separated arch-os stage names to run in Stage 2, e.g. `x64-linux,aarch64-linux`. Leave blank for all architectures. To be removed once the pipeline is stable. |
| `FORK` | `adoptium` | GitHub organisation / fork that owns the `temurin-build` repository being tested |
| `BRANCH` | `master` | Branch in `FORK` to check out |

### Platform / Version Support Matrix

Defined in `ARCH_STAGE_DEFS` in the Jenkinsfile. Each entry maps a stage name to `[nodeLabel, extraFlags, firstJDK, lastJDK]`.

| Stage Name | Node Label | First JDK | Last JDK |
|---|---|---|---|
| `x64-linux` | `ci.role.test&&hw.arch.x86&&sw.os.linux` | 8 | ongoing |
| `aarch64-linux` | `ci.role.test&&hw.arch.aarch64&&sw.os.linux` | 8 | ongoing |
| `x64-alpine-linux` | `ci.role.test&&hw.arch.x86&&sw.os.alpine-linux` | 8 | ongoing |
| `aarch64-alpine-linux` | `ci.role.test&&hw.arch.aarch64&&sw.os.alpine-linux` | 21 | ongoing |
| `x64-mac` | `ci.role.test&&hw.arch.x86&&(sw.os.osx\|\|sw.os.mac)` | 8 | ongoing |
| `aarch64-mac` | `ci.role.test&&hw.arch.aarch64&&(sw.os.osx\|\|sw.os.mac)` | 11 | ongoing |
| `s390x-linux` | `ci.role.test&&hw.arch.s390x&&sw.os.linux` | 11 | ongoing |
| `ppc64le-linux` | `ci.role.test&&hw.arch.ppc64le&&sw.os.linux` | 8 | ongoing |
| `ppc64-aix` | `ci.role.test&&hw.arch.ppc64&&sw.os.aix&&sw.os.aix.7_2TL5` | 8 | ongoing |
| `riscv64-linux` | `ci.role.test&&hw.arch.riscv&&sw.os.linux` | 17 | ongoing |
| `arm-linux` | `ci.role.test&&hw.arch.aarch32&&sw.os.linux` | 8 | 20 |
| `x64-windows` | `ci.role.test&&hw.arch.x86&&sw.os.windows` | 8 | ongoing |
| `aarch64-windows` | `ci.role.test&&hw.arch.aarch64&&sw.os.windows` | 21 | ongoing |

---

## Core Script: `release_download_test_new.sh`

### Usage

```bash
bash release_download_test_new.sh [OPTIONS] TAG
```

`TAG` can also be supplied via the `$TAG` environment variable. `$WORKSPACE` defaults to `$PWD`.

### Options

| Flag | Description |
|---|---|
| `-k` | Keep staging area after validation (debug/testing only) |
| `-s` | Skip downloading release artifacts (requires staging to already exist) |
| `-a` | Enable ANSI colour output |
| `-v` | Enable verbose per-file logging |
| `-b` | Skip binary string checks (GCC/GLIBC via `strings`); run GPG/SHA/archive/SBOM checks only |
| `-g` | **GPG-only mode**: download all files (or filtered subset if `-F` set), verify GPG/SHA256 sigs and archive integrity, then exit. Used by the central pipeline node (Stage 1a). |
| `-G` | **Skip-GPG mode**: download only files for the `-A`/`-O` arch/os pair; skip GPG and archive checks (already done centrally). Used by each arch-specific node (Stage 2). Requires `-A` and `-O`. |
| `-c` | **SBOM-only mode**: validate SBOMs for all arches from the central staging area, then exit. Used by the central pipeline node (Stage 1b). Requires staging already populated by `-g`. |
| `-C` | **Skip-SBOM mode**: skip SBOM validation (already done centrally by `-c`). Used alongside `-G` on arch nodes. |
| `-A arch` | Override arch for tarball matching and binary checks (bypasses `uname` detection) |
| `-O os` | Override OS for tarball matching and binary checks (bypasses `uname` detection) |
| `-F list` | Comma-separated `arch_os` tokens to download in `-g` mode, e.g. `x64_linux,aarch64_linux`. Arch-agnostic files (sources, release-notes, AQAvit) are always included. Leave unset to download the full release. |
| `-h` | Show help |

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | Fundamental setup error (e.g. no files downloaded) |
| `2` | GPG signature verification failed |
| `3` | SHA256 checksum failed |
| `4` | GCC/GLIBC version not as expected |
| `5` | CycloneDX validation checks failed |
| `6` | SBOM contents did not meet expectations |

If multiple checks fail the highest exit code is returned. Look for `ERROR:` in the output to locate specific failures.

### Mode Flag Reference

The flags compose to cover the three pipeline stages:

| Mode | Flags | Used by |
|---|---|---|
| Full validation (standalone) | _(no mode flags)_ | Local use / single-node CI |
| Central GPG+archive | `-g -k` | Stage 1a (`worker` node) |
| Central SBOM | `-c` | Stage 1b (`worker` node) |
| Arch-node binary check | `-G -C -A <arch> -O <os>` | Stage 2 (native agent per arch) |

### Key Functions

| Function | Description |
|---|---|
| `extract_major_version` | Parses `TAG` to set `MAJOR_VERSION`. Handles GA (`jdk-21.0.3+9`), JDK 8 (`jdk8u422-b05`), and EA beta (`jdk21u-2024-01-01-beta`) formats. |
| `download_jdk_releases` | Fetches the GitHub Releases JSON for the relevant `temurinXX-binaries` repository. EA beta tags are fetched directly by tag name; all others use the paginated list endpoint. |
| `download_release_files` | Downloads all release artifacts to `$WORKSPACE/staging/$TAG`. Supports arch filtering via `-F` (central) and `-G` (arch-node). |
| `import_gpg_key` | Imports and trusts the Temurin GPG key (`3B04D753...`) into an isolated per-arch/os `GNUPGHOME`. |
| `verify_gpg_signatures` | Verifies GPG signatures and SHA256 checksums for all archives and SBOM JSON files. Accumulates per-platform results in `_GPG_PER_ARCH`. |
| `verify_valid_archives` | Checks that `.tar.gz` and `.zip` archives can be extracted and contain a minimum number of files. |
| `verify_working_executables` | Extracts JRE/JDK tarballs and runs `java -version` when executing natively. Skips execution (but still extracts) when running cross-arch via `-A`/`-O`. |
| `verify_glibc_version` | Checks for `GLIBC_*` versioned symbols in the JDK binary via `strings`. glibc Linux only; skipped on Alpine, macOS, Windows, AIX. |
| `verify_compiler_version` | Verifies the GCC version string embedded in the JDK binary via `strings`. Version varies by JDK major and platform. Skipped on AIX, macOS, Windows. |
| `verify_windows_compiler_version` | Runs `java.exe -Xinternalversion` and checks the MS VC++ toolset version. Expects Visual Studio 2022 (toolset ≥ 1930). Windows only. |
| `verify_sboms` | Validates all SBOM JSON files via `validateSBOM.sh`. Accumulates per-platform results in `_SBOM_PER_ARCH`. |
| `write_platform_results` | Writes a single `PASS`/`FAIL` token to `staging/$TAG/.results/<phase>_<arch_os>.result`. |
| `flush_results_to_disk` | Flushes all entries from a per-arch accumulator (`_GPG_PER_ARCH` / `_SBOM_PER_ARCH`) to individual result files. |
| `read_platform_results` | Reads GPG, archive, and SBOM result files written by the central stages into `_PHASE_SIGNATURES`, `_PHASE_ARCHIVES`, and `_PHASE_SBOM`. Called in arch-node mode (`-G`) before printing the summary. |
| `print_summary` | Prints a phase-by-phase validation summary table to stdout. Always printed (not verbose-gated). |

---

## Local Multi-Arch Helper: `validate_all_archs.sh`

Runs `release_download_test_new.sh` for every supported arch/os in parallel, reusing an already-downloaded staging directory (`-s` flag). Useful for local validation after a single download.

### Usage

```bash
# 1. Download the release once
bash release_download_test_new.sh -k jdk-21.0.3+9

# 2. Validate all arch/os combinations in parallel
bash validate_all_archs.sh [-j N] [-a] [-k] jdk-21.0.3+9
```

### Options

| Flag | Description |
|---|---|
| `-j N` | Max parallel jobs (default: one per arch/os, all at once) |
| `-a` | Enable ANSI colour output |
| `-k` | Keep staging area after validation |
| `-h` | Show help |

### Supported Combinations

| Arch | OS | Binary Check Mode |
|---|---|---|
| `x64` | `linux` | native `java -version` + `strings` |
| `aarch64` | `linux` | native `java -version` + `strings` |
| `x64` | `alpine-linux` | `strings` only (arch override) |
| `aarch64` | `alpine-linux` | `strings` only (arch override) |
| `x64` | `mac` | skipped (`-b`) |
| `aarch64` | `mac` | skipped (`-b`) |
| `s390x` | `linux` | `strings` only (arch override) |
| `ppc64le` | `linux` | `strings` only (arch override) |
| `ppc64` | `aix` | skipped (`-b`) |
| `riscv64` | `linux` | `strings` only (arch override) |
| `arm` | `linux` | `strings` only (arch override) |
| `x64` | `windows` | skipped (`-b`) |
| `aarch64` | `windows` | skipped (`-b`) |

Per-arch logs are written to `$WORKSPACE/staging/$TAG/validation-logs/<arch>_<os>.log`.

Exit code is the number of failed arch/os combinations (0 = all passed).

---

## Unit Tests: `unit_tests/test_release_download.sh`

Tests the pure-logic functions in `release_download_test_new.sh` without any network access, GPG operations, or downloads.

### Running

```bash
bash tooling/release_download_test/unit_tests/test_release_download.sh
```

Run from the repository root. Exit code 0 = all tests passed.

### Test Coverage

| Test Group | What is Tested |
|---|---|
| `extract_major_version` | Tag parsing for GA (`jdk-21.0.3+9`), JDK 8 (`jdk8u382-b05`), JDK 17 (`jdk-17.0.10+7`), and EA beta (`jdk21u-2024-01-01-beta`, `jdk26u-2026-07-25-beta`) formats |
| `determine_arch` | `uname -m` → Temurin arch token mapping for `x86_64`, `aarch64`, `ppc64le`, `s390x`, `armv7l`, `ppc64`, `riscv64` |
| `determine_os` | `uname -s` → Temurin OS token mapping for `Linux`, `Darwin`, `CYGWIN_NT-*`, `AIX`, and Alpine Linux (`/etc/alpine-release` present) |
| `parse_options` | All flags: `-k`, `-s`, `-a`, `-b`, `-A`, `-O`, `-c`, `-C`; positional `TAG` argument; combined multi-flag invocations |
| Phase-state flags | `GPG_ONLY=true` sets binary+SBOM phases to `SKIP`; `SBOM_ONLY=true` sets download/GPG/archive/binary phases to `SKIP`; `SKIP_SBOM=true` sets SBOM phase to `SKIP` |
| `write_platform_results` | Creates result files with correct content for `gpg`, `sbom` phases and various arch/os combinations |
| `flush_results_to_disk` | Writes multiple entries from an accumulator to individual result files |
| `read_platform_results` | Reads GPG/archive/SBOM result files into phase variables; returns `N/A` for missing files; propagates `FAIL` correctly |
| Arch/OS filename regex | `sed` pattern used in `verify_gpg_signatures` and `verify_sboms` to extract `arch/os` from filenames — covers GA (`OpenJDK21U-*`) and EA (`OpenJDK-*`) formats, arch-agnostic files (sources, release-notes) must yield empty |
| `native_arch` / `native_os` | Returns a known valid arch/OS token for the current machine |
