# Plan: Rework `release_download_test.sh` for Multi-Architecture Support and Testability

## Top-Level Overview

`tooling/release_download_test.sh` drives post-release validation of Temurin binary
artefacts. It downloads a full release from GitHub, verifies GPG/SHA256 signatures, checks
archive integrity, runs `java -version` on the native binary, checks GLIBC/GCC compiler
strings embedded in the binary, and delegates SBOM validation to `validateSBOM.sh`.

Three concrete problems prompted this work:

1. **Architecture hard-coding** — PR #4385 was a tactical fix after the Jenkins worker for
   the `download_and_sbom_validation` job was moved from an OSUOSL aarch64 machine to an
   x64 Hetzner machine. The GLIBC version check hard-coded the x64 value and failed on the
   old aarch64 runner. Issue #4386 captures the proper fix: `determine_arch()` only maps
   three of the eight architectures the project builds for, and `determine_os()` has no
   awareness of AIX or Alpine Linux.

2. **No testability** — There is no way to validate script logic without a live download.
   Issue #4386 notes that a first local attempt produced `ERROR: SBOM_LOCATION could not be
   found`, meaning even basic invocation is opaque without downloading several GB of
   artefacts. There is no unit-test harness and no CI gate on PRs that touch the script.

3. **Single-node Jenkins job** — The job currently runs as a single shell step on whichever
   x64 `jenkins-hetzner-worker` happens to be free. It therefore only exercises binaries
   for the architecture of that one machine. The job needs to fan out to architecture-
   specific agents so every platform's binaries are validated on hardware that can at least
   run `strings` against them, and on machines that can natively execute the JRE for the
   matching platforms.

The rework is split into five focused sub-tasks, each independently reviewable:

1. Extend `determine_arch()` and `determine_os()` to cover every architecture and OS the
   project builds for.
2. Add `-A <arch>` and `-O <os>` override flags so the arch/os used for binary checks can
   be supplied explicitly, independent of the machine's `uname` output.
3. Add a `-b` flag to skip the `strings`-based GCC/GLIBC binary checks entirely, for
   callers that only need GPG/SHA/archive/SBOM validation.
4. Add a shell unit-test script and a GitHub Actions workflow that gates PRs touching the
   script.
5. Add `tooling/Jenkinsfile.release_download_test`, a Declarative Pipeline that fans the
   validation job out in parallel across one agent per supported architecture.

Sub-tasks 1–3 all touch `release_download_test_new.sh` and should be implemented in order.
Sub-task 4 depends on sub-tasks 1–3 (so it can test the new flags). Sub-task 5 depends on
sub-tasks 2 and 3 (the Jenkinsfile passes `-A`/`-O`/`-b` to the shell script).

> **Development isolation:** All shell-script changes are made to a new file
> `tooling/release_download_test_new.sh` (a copy of the original). This keeps the working
> script untouched during development and review. The Jenkinsfile and unit tests reference
> this new filename. Once reviewed and approved the new file will replace the original.

---

## Sub-Task 1 — Extend Architecture and OS Detection

### Intent
`determine_arch()` only maps `x86_64`, `aarch64`, and `ppc64le`. When run on any other
machine it calls `exit 1` with a bare "Unknown machine" message. The project actively
builds and tests on `s390x`, `armv7l` (arm32), `riscv64`, and `ppc64` (AIX).

`determine_os()` has no case for AIX (`uname -s` returns `AIX`) and no way to distinguish
Alpine Linux from standard glibc Linux. Both are needed because AIX tarballs use a
different filename convention and Alpine uses musl rather than glibc.

### Expected Outcomes
- `determine_arch()` maps all eight architectures the project supports without `exit 1`.
- `determine_os()` handles `AIX` as a distinct OS value (`aix`).
- `determine_os()` detects Alpine Linux by checking `/etc/alpine-release` and sets
  `OS=alpine-linux` when present.
- Running the script on an `s390x`, `armv7l`, `riscv64`, `ppc64`, or AIX machine no
  longer exits with "Unknown machine" or "Unknown kernel".

### Todo List
1. In `determine_arch()`, add the following `case` branches:
   - `s390x`    → `ARCH=s390x`
   - `armv7l`   → `ARCH=arm`
   - `ppc64`)   → `ARCH=ppc64`
   - `riscv64`) → `ARCH=riscv64`
2. In `determine_os()`, add:
   - `AIX*)  OS=aix` case branch.
   - After the `Linux*` branch sets `OS=linux`, add a check:
     `[ -f /etc/alpine-release ] && OS=alpine-linux`
3. Review `verify_working_executables()`, `verify_glibc_version()`, and
   `verify_gcc_version()` — confirm they already guard themselves with
   `ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz` so newly supported arches that
   have no matching tarball in a given release (e.g. arm32 binaries not being part of all
   releases) naturally skip without error. No code change needed if the guard is already
   correct; document this explicitly in a comment if not.

### Relevant Context
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:305) —
  `determine_os()` (line numbers match original until edits shift them).
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:322) —
  `determine_arch()`.
- [`tooling/build_autotriage/build_autotriage.sh`](tooling/build_autotriage/build_autotriage.sh:49) —
  canonical platform/arch matrix (source of truth for which arches are supported).

### Status
[x] done

---

## Sub-Task 2 — Add `-A arch` and `-O os` Override Flags

### Intent
Sub-task 1 makes the script safe to run on any supported machine. However the Jenkins job
runs on a single x64 Hetzner worker and needs to exercise the `strings`-based GCC/GLIBC
checks for all architectures. Those checks do not execute the binary — they read it with
`strings` — so they can run cross-arch as long as the script is pointed at the right
tarball filename. Adding explicit `-A` and `-O` override flags lets the Jenkinsfile tell
the script which arch/os to target without relying on `uname`.

The `java -version` execution check, by contrast, genuinely requires native hardware. The
override logic must therefore skip `verify_working_executables()` when the supplied `-A`/`-O`
does not match the machine's native `uname` output.

### Expected Outcomes
- `-A <arch>` sets the arch used for tarball filename matching and binary checks, bypassing
  `determine_arch()`.
- `-O <os>` sets the OS token used for tarball filename matching, bypassing `determine_os()`.
- When `-A`/`-O` is set and does not match the machine's native `uname -m`/`uname -s`,
  `verify_working_executables()` prints a verbose skip message and returns without running
  `java -version`. `verify_glibc_version()` and `verify_gcc_version()` still run.
- `usage()` documents the new flags.

### Todo List
1. Add `OVERRIDE_ARCH=""` and `OVERRIDE_OS=""` variables near the top of the script
   alongside the existing `KEEP_STAGING`, `SKIP_DOWNLOADING`, etc. variables.
2. Add `-A` and `-O` cases to `getopts` in `parse_options()`, assigning to `OVERRIDE_ARCH`
   and `OVERRIDE_OS` respectively.
3. In the main body, after the `determine_os` / `determine_arch` calls, apply any overrides:
   ```sh
   [ -n "${OVERRIDE_ARCH}" ] && ARCH="${OVERRIDE_ARCH}"
   [ -n "${OVERRIDE_OS}" ]   && OS="${OVERRIDE_OS}"
   ```
4. In `verify_working_executables()`, before extracting and running the JRE, check whether
   `ARCH` and `OS` match the current machine's native values. Add a helper that maps
   `uname -m` to the Temurin arch token (reusing the same mapping as `determine_arch`) and
   similarly for `uname -s`. If they do not match, print a verbose message and return 0.
5. Update `usage()` with `-A <arch>` and `-O <os>` entries and a one-line explanation.

### Relevant Context
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:35) — top-level
  variable declarations.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:70) —
  `parse_options()`.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:339) —
  `verify_working_executables()`.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:464) — main body
  where `determine_os` / `determine_arch` are called.

### Status
[x] done

---

## Sub-Task 3 — Make Binary String Checks OS/Arch-Aware and Add `-b` Skip Flag

### Intent
The current `verify_glibc_version()` and `verify_gcc_version()` functions unconditionally
run `strings` against the extracted JRE binary and check for glibc and GCC version strings.
This is only valid for glibc-based Linux builds. Other platforms use entirely different
toolchains:

| Platform            | Compiler toolchain          | C runtime | GLIBC check? | GCC strings check? |
|---------------------|-----------------------------|-----------|-------------|-------------------|
| Linux (glibc)       | GCC (version varies by JDK) | glibc     | ✅ yes       | ✅ yes             |
| Alpine Linux        | GCC 10.3.1 (musl devkit)    | musl libc | ❌ no        | ✅ yes (different expected version) |
| macOS               | clang/LLVM (Xcode 15.2)     | libSystem | ❌ no        | ❌ no              |
| Windows             | MSVC 2022                   | MSVCRT    | ❌ no        | ❌ no              |
| AIX                 | XLC (≤JDK21) / clang (>21)  | AIX libc  | ❌ no        | ❌ no              |
| riscv64 Linux       | GCC 14.2.0                  | glibc 2.27 | ✅ yes (different expected version) | ✅ yes |

The `validateSBOMcontent.sh` script already encodes the correct expected values per
platform (sourced from that file). The binary string checks in `release_download_test.sh`
must be aligned with this same logic — only running GLIBC checks on glibc Linux, and only
running GCC string checks on GCC-compiled binaries.

A `-b` flag also allows callers to skip all binary string checks entirely (e.g. on AIX
where `strings` output format differs, or in pure GPG/SBOM-only validation workflows).

### Expected Outcomes
- `verify_glibc_version()` only runs when `OS` is `linux` or `alpine-linux` **and** the
  glibc check is applicable for the arch. Specifically:
  - `alpine-linux` uses musl — GLIBC check must be **skipped** for Alpine.
  - `linux` with `arm` arch uses GLIBC 2.23 (Ubuntu 16.04 devkit).
  - `linux` with `x64` arch and JDK < 20 uses GLIBC 2.12 (CentOS 6 devkit).
  - `linux` with all other arches uses GLIBC 2.17 (CentOS 7 devkit), except `riscv64`
    which uses GLIBC 2.27 (Fedora 28).
  - For all non-Linux OSes (mac, windows, aix), `verify_glibc_version()` prints a verbose
    skip message and returns without error.
- `verify_gcc_version()` only runs when the binary is GCC-compiled:
  - `linux` (all arches): GCC — expected version varies by JDK major (7.5.0 / 10.3.0 /
    11.3.0 / 14.2.0), with `riscv64` always using 14.2.0 and `alpine-linux` always using
    10.3.1.
  - `mac`, `windows`, `aix`: not GCC-compiled — function skips with a verbose message.
- New `-b` flag sets `SKIP_BINARY_CHECKS=true`, bypassing all three binary-inspection
  functions (`verify_working_executables`, `verify_glibc_version`, `verify_gcc_version`)
  and the `rm -rf tarballtest` cleanup. A single informational message is printed.
- `usage()` documents the new `-b` flag.

### Todo List
1. Add `SKIP_BINARY_CHECKS=false` near the top of the script with the other flag variables.
2. Add a `-b` case to `getopts` in `parse_options()`.
3. Refactor `verify_glibc_version()`:
   - Add an early return when `OS` is not `linux` (i.e. skip for `alpine-linux`, `mac`,
     `windows`, `aix`) with a verbose skip message naming the reason.
   - Replace the hard-coded `GLIBC_2.2.5` check with logic that selects the expected
     GLIBC version based on `ARCH` and `MAJOR_VERSION`, matching the table in
     `validateSBOMcontent.sh` lines 55–75:
     - `arm` → `2.23`
     - `riscv64` → `2.27`
     - `x64` + `MAJOR_VERSION` < 20 → `2.12`
     - all other linux arches → `2.17`
4. Refactor `verify_gcc_version()`:
   - Add an early return when `OS` is `mac`, `windows`, or `aix` with a verbose skip
     message.
   - For `alpine-linux`, use a fixed expected GCC of `10.3.1` regardless of `MAJOR_VERSION`
     (matches `validateSBOMcontent.sh` line 52).
   - For `riscv64` on `linux`, use `14.2.0` regardless of `MAJOR_VERSION` (line 72).
   - Retain the existing `MAJOR_VERSION`-based lookup for all other linux arches, updating
     the version table to include JDK 20–24 → `11.3.0` (the current code only maps 21).
5. In the main body, wrap the three binary-check calls and `rm -rf tarballtest` in a
   single `if [ "${SKIP_BINARY_CHECKS}" = "false" ]; then ... fi` block.
6. Update `usage()` with a `-b` entry.

### Relevant Context
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:365) —
  `verify_glibc_version()` with the hard-coded `GLIBC_2.2.5` check.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:382) —
  `verify_gcc_version()` with the version-by-major lookup.
- [`tooling/validateSBOMcontent.sh`](tooling/validateSBOMcontent.sh:42) — the definitive
  per-platform expected GLIBC/GCC/compiler values; the binary checks must mirror this.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:468) — binary
  check calls and `rm -rf tarballtest` in the main body.

### Status
[x] done

---

## Sub-Task 4 — Add Unit Tests and a CI Workflow

### Intent
There is currently no way to validate the script's logic without a full live download.
A unit-test harness covering the pure-logic functions prevents future regressions, gives
contributors confidence when changing the script, and verifies the new `-A`/`-O`/`-b`
flags from sub-tasks 2 and 3 work correctly.

The existing pattern in `tooling/reproducible/unit_tests/test_pandoc_version_from_sbom.sh`
uses a simple `assertEquals()` helper in plain bash with no external dependencies — we
follow the same convention.

A new GitHub Actions workflow gates PRs that touch the script, mirroring how
`.github/workflows/testcyclonedx.yml` gates SBOM changes.

### Expected Outcomes
- `tooling/unit_tests/test_release_download.sh` exists and passes with `bash` on Linux
  without network access.
- The test script covers:
  - `extract_major_version` for all three tag formats: `jdk8u382-b05`, `jdk-21.0.3+9`
    (GA), `jdk21u-2024-01-01-00-00-beta` (EA).
  - `determine_arch` for every `uname -m` value now mapped (including the new ones from
    sub-task 1).
  - `determine_os` for Linux, macOS, Alpine Linux (mocked `/etc/alpine-release`), and AIX.
  - `parse_options` accepting valid flag combinations (`-k`, `-s`, `-a`, `-v`, `-b`,
    `-A x64`, `-O linux`) and correctly populating variables.
- `release_download_test.sh` is sourceable for testing: the main body is wrapped in a
  `if [ "${TEST_MODE:-false}" != "true" ]` guard so sourcing with `TEST_MODE=true` loads
  all functions without executing the pipeline.
- `.github/workflows/test-release-download.yml` runs `test_release_download.sh` on
  `ubuntu-latest` on every PR touching either the script or the test file.
- Test output follows the existing convention: `PASS: <test name>` on success, `FAIL: ...`
  with expected/actual on failure, exit 1 on any failure.

### Todo List
1. Add a `TEST_MODE` guard to `release_download_test_new.sh`: wrap the main body (from
   `parse_options "$@"` to the final `exit ${RC}`) in
   `if [ "${TEST_MODE:-false}" != "true" ]; then ... fi`.
2. Create `tooling/unit_tests/` directory.
3. Write `tooling/unit_tests/test_release_download.sh`:
   - Set `TEST_MODE=true` and `source` the script under test using `SCRIPT_DIR` set to the
     `tooling/` directory.
   - Implement an `assertEquals()` function matching the existing pattern.
   - For `determine_arch` and `determine_os` tests, mock `uname` using a local function
     override (`uname() { echo "$MOCK_UNAME"; }`) to avoid depending on the test machine's
     actual hardware.
   - Cover all cases listed in Expected Outcomes above.
   - Print `PASS: <all tests passed>` at the end and exit 0.
4. Create `.github/workflows/test-release-download.yml`:
   - Trigger: `pull_request` paths `tooling/release_download_test_new.sh`,
     `tooling/unit_tests/test_release_download.sh`, and
     `tooling/Jenkinsfile.release_download_test`.
   - Single job on `ubuntu-latest`: `actions/checkout` (pinned hash) then
     `bash tooling/unit_tests/test_release_download.sh`.
   - Follow the pinned-action-hash convention used throughout the repo's other workflows.

### Relevant Context
- [`tooling/reproducible/unit_tests/test_pandoc_version_from_sbom.sh`](tooling/reproducible/unit_tests/test_pandoc_version_from_sbom.sh) —
  existing test pattern to follow exactly.
- [`.github/workflows/testcyclonedx.yml`](.github/workflows/testcyclonedx.yml) —
  existing workflow structure to mirror.
- [`tooling/release_download_test_new.sh`](tooling/release_download_test_new.sh:424) — main body
  starts at `parse_options "$@"` on line 424.

### Status
[x] done

---

## Sub-Task 5 — Jenkinsfile for Multi-Arch Fan-out

### Intent
The root cause of PR #4385 is that the download validation job runs as a single shell step
on a single-architecture machine. When the node type changed, the binary checks silently
stopped covering the old architecture.

The fix is a Declarative Pipeline `tooling/Jenkinsfile.release_download_test` stored in
this repository alongside the shell script. Jenkins can be pointed directly at this file
as the pipeline definition. The pipeline fans out in parallel to one agent per supported
architecture. Each agent independently downloads the release, runs `release_download_test.sh`
with the appropriate `-A`/`-O`/`-b` flags, and removes its staging directory afterwards to
keep disk usage bounded. Failures in individual architecture stages are surfaced as unstable
rather than aborting the other stages.

Each agent re-downloads the full release independently. This is simpler than stashing
artefacts across agents (which have heterogeneous OS types including AIX) and is safe
because the `-C -` resume flag is already present in the `curl` call in the script.

Node labels use the `&&`-separated compound label convention from `ci-jenkins-pipelines`,
e.g. `build&&linux&&x64&&dockerBuild&&dynamicAzure` rather than machine-specific hostnames.
This means any correctly labelled agent in the pool can pick up each stage, not just a
named subset of hosts.

### Expected Outcomes
- `tooling/Jenkinsfile.release_download_test` exists in this repository.
- It is a Declarative Pipeline (`pipeline { agent none ... }`) with:
  - A `parameters` block declaring `TAG` (required string, the release tag to validate)
    and `TEMURIN_BUILD_REF` (optional string, default `master`, so the job can test a PR
    branch of this script).
  - A single `stage('Validate')` containing a `parallel` block with one named entry per
    architecture, each defined as a `node('<label expression>') { ... }` scripted block.
  - `failFast false` on the parallel block so all architectures are always attempted.
  - A top-level `post { always { } }` block that echoes a completion message.
- The per-architecture stages, their label expressions, and script flags are:

  | Stage name           | Agent label expression                         | Script flags                    | `java -version`? | Notes |
  |----------------------|------------------------------------------------|---------------------------------|-----------------|-------|
  | `x64-linux`          | `build&&linux&&x64&&dockerBuild&&dynamicAzure` | `-A x64 -O linux`               | ✅ native        | |
  | `aarch64-linux`      | `docker&&linux&&aarch64`                       | `-A aarch64 -O linux`           | ✅ native        | |
  | `x64-alpine-linux`   | `build&&linux&&x64&&dockerBuild&&dynamicAzure` | `-A x64 -O alpine-linux -b`     | ❌ musl, no glibc/GCC strings | same pool as x64-linux; docker image differs |
  | `aarch64-alpine-linux` | `docker&&linux&&aarch64`                     | `-A aarch64 -O alpine-linux -b` | ❌ musl, no glibc/GCC strings | same pool as aarch64-linux |
  | `x64-mac`            | `build&&macos&&x64`                            | `-A x64 -O mac -b`              | ❌ clang, not GCC | |
  | `aarch64-mac`        | `build&&macos&&aarch64`                        | `-A aarch64 -O mac -b`          | ❌ clang, not GCC | |
  | `s390x-linux`        | `docker&&s390x&&dockerBuild`                   | `-A s390x -O linux -b`          | ❌ strings only  | |
  | `ppc64le-linux`      | `build&&dockerBuild&&ppc64le`                  | `-A ppc64le -O linux -b`        | ❌ strings only  | |
  | `ppc64-aix`          | `build&&aix`                                   | `-A ppc64 -O aix -b`            | ❌ XLC/clang, skip binary checks | |
  | `riscv64-linux`      | `build&&linux&&x64&&dockerBuild&&dynamicAzure` | `-A riscv64 -O linux -b`        | ❌ cross-compiled via QEMU | runs in docker with `--platform linux/riscv64` on x64 host |
  | `arm-linux`          | `docker&&linux&&aarch64`                       | `-A arm -O linux -b`            | ❌ strings only  | arm32 tarballs present only in JDK ≤ 20 |
  | `x64-windows`        | `build&&windows&&x64`                          | `-A x64 -O windows -b`          | ❌ MSVC, skip binary checks | |
  | `aarch64-windows`    | `build&&windows&&aarch64`                      | `-A aarch64 -O windows -b`      | ❌ cross-compiled, skip binary checks | present from JDK 21 only |

  > **Notes on label expressions:** The macOS and Windows compound labels (`build&&macos&&*`,
  > `build&&windows&&*`) should be confirmed against the live Jenkins agent label assignments
  > before wiring up — macOS agents typically also carry an Xcode version label
  > (e.g. `xcode15.0.1`) but this is not required for the download test. The riscv64 stage
  > runs on the same x64 Linux pool that builds it (cross-compiled via QEMU); the
  > `-A riscv64` flag ensures the script targets the riscv64 tarball filenames. Alpine
  > stages run on the same host pools as their glibc counterparts (builds use Docker images).

- Inside each `node` block:
  1. Checkout `temurin-build` at `TEMURIN_BUILD_REF`.
  2. Run `tooling/release_download_test_new.sh -v -a -A <arch> -O <os> [flags] ${TAG}` via
     `sh`.
  3. In a `post { always { sh 'rm -rf "${WORKSPACE}/staging"' } }` nested inside the
     `node` block, remove the staging directory to reclaim disk space.
- `warnError('stage-name')` wraps each `node` block so a failure marks the stage as
  unstable rather than killing the parallel group.
- A header comment block explains the purpose, parameters, the label convention, and how to
  wire this Jenkinsfile into an existing Jenkins Pipeline job (point it at the SCM path
  `tooling/Jenkinsfile.release_download_test`).

### Todo List
1. Create `tooling/Jenkinsfile.release_download_test` with the structure described above.
2. Write the header comment block (licence header + purpose + parameter docs + label
   convention note + usage note for wiring into Jenkins).
3. Define the `parameters` block with `TAG` and `TEMURIN_BUILD_REF`.
4. Define a Groovy map `def nodeLabels` at the top of the `stage('Validate')` script block
   mapping each stage name to its label expression and flags tuple, keeping the stage
   definitions data-driven and easy to extend.
5. Build the `parallel` map by iterating `nodeLabels`, wrapping each entry in `warnError`
   and a `node('<label>') { checkout ...; sh ...; post { always { ... } } }` block.
6. Set `failFast false` on the parallel invocation.
7. Add the top-level `post { always { echo 'Validation complete' } }` block.

### Relevant Context
- [`sbin/solaris/simplepipe.groovy`](sbin/solaris/simplepipe.groovy) — the only existing
  Groovy pipeline in this repo; shows `node('worker')` and `warnError` patterns.
- `ci-jenkins-pipelines` label convention (from `jdk21u_pipeline_config.groovy` and the
  user-provided pattern):
  ```groovy
  (arch == 'x64')     ? 'build&&linux&&x64&&dockerBuild&&dynamicAzure'
  (arch == 'aarch64') ? 'docker&&linux&&aarch64'
  (arch == 'ppc64le') ? 'build&&dockerBuild&&ppc64le'
  (arch == 's390x')   ? 'docker&&s390x&&dockerBuild'
  (arch == 'riscv64') ? 'dockerBuild&&linux&&riscv64&&dockerInstaller'
  // AIX: 'build&&aix'
  ```
- Sub-tasks 2 and 3 must be complete before this Jenkinsfile can be used, as it depends on
  the `-A`, `-O`, and `-b` flags they add.

### Status
[x] done
