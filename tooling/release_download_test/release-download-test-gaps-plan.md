# Plan: Fix Gaps in release_download_test_new.sh and Jenkinsfile

## Top-Level Overview

Four concrete gaps need to be fixed across the shell script and Jenkinsfile introduced in
the rework:

1. **GLIBC check is too weak** — `verify_glibc_version()` checks only the universal sentinel
   `GLIBC_2.2.5` rather than the per-arch/version devkit values that `validateSBOMcontent.sh`
   uses as the source of truth. It should mirror that logic exactly.

2. **Compiler checks are missing for AIX and macOS** — `verify_gcc_version()` currently
   skips AIX and macOS entirely. AIX uses XLC (JDK ≤ 21) or clang (JDK ≥ 22); macOS uses
   clang/Xcode. Both can be verified via `strings` on a native agent of the correct type.
   The function must be broadened (and renamed) to cover all compiler toolchains.

3. **Output is too noisy by default** — in normal (non-verbose) mode every per-file PASS,
   download progress line, and section banner is printed unconditionally. The Jenkins job
   runs 13 stages in parallel and each stage produces hundreds of lines. Normal mode should
   suppress everything except `ERROR:` lines and the final summary table; all intermediate
   progress becomes verbose-only.

4. **Jenkinsfile node labels are wrong** — the current labels use the old
   `ci-jenkins-pipelines` compound format (`build&&linux&&x64&&dockerBuild&&dynamicAzure`).
   They must be replaced with the AQA-test standard format (`ci.role.test&&hw.arch.x86&&sw.os.linux`).
   Additionally, every architecture must run on a host of that architecture so that
   `java -version` and all binary string checks execute natively — the `-b` skip-binary
   flag is removed from all stages; only Windows retains it (MSVC PE binary string format
   is not compatible with GNU `strings` on a standard shell agent).

The work is split into four independently reviewable sub-tasks in dependency order.
Sub-task 2 depends on Sub-task 1 (it broadens the same function). Sub-tasks 3 and 4 are
independent of each other but both depend on Sub-tasks 1 and 2 being complete.

---

## Sub-Task 1 — Implement Full Per-Arch GLIBC Version Check

### Intent

The current `verify_glibc_version()` checks that the binary contains the string
`GLIBC_2.2.5`, which is the minimum ELF symbol present in *any* glibc-linked binary and
only confirms the binary is glibc-linked. It does not verify the devkit version used to
build Temurin. `validateSBOMcontent.sh` lines 55–75 encode the definitive per-arch/version
expected values; the binary strings check must mirror this exactly so that a wrong devkit
produces an error immediately, without waiting for the SBOM phase.

### Expected Outcomes

- `verify_glibc_version()` selects `expected_glibc` based on `ARCH` and `MAJOR_VERSION`
  using the same logic as `validateSBOMcontent.sh`:
  - `arm` / armv7l                                        → `2.23` (Ubuntu 16.04 devkit)
  - `riscv64`                                             → `2.27` (Fedora 28 devkit)
  - `x64` with `MAJOR_VERSION` < 20                       → `2.12` (CentOS 6 devkit)
  - all other glibc Linux arches (x64≥20, aarch64, s390x, ppc64le, ppc64) → `2.17` (CentOS 7 devkit)
- Alpine Linux (`OS=alpine-linux`) still returns early — musl does not use GLIBC versioned
  symbols, and this is consistent with `validateSBOMcontent.sh` which has no GLIBC entry
  for Alpine.
- macOS, Windows, AIX still return early (unchanged).
- The `strings` check looks for `^GLIBC_${expected_glibc}` in the binary.
- The detected value and expected value are both logged at the info level (already present
  in the current code; no change to that logging).
- The unit test file `unit_tests/test_release_download.sh` does **not** test
  `verify_glibc_version()` directly (it requires a real binary); no unit test changes are
  needed for this sub-task.

### Todo List

1. In `verify_glibc_version()` in `release_download_test_new.sh`, replace the hard-coded
   `expected_glibc="2.2.5"` with a conditional block that mirrors the logic in
   `validateSBOMcontent.sh` lines 55–75:
   - Start with the default `2.17`
   - Override to `2.12` when `ARCH=x64` and `MAJOR_VERSION` is less than 20
   - Override to `2.23` when `ARCH=arm`
   - Override to `2.27` when `ARCH=riscv64`
2. Update the `grep` check from `^GLIBC_2.2.5` to `^GLIBC_${expected_glibc}`.
3. Update the error message to include the arch and version context, e.g.:
   `"Minimum GLIBC symbol GLIBC_${expected_glibc} not found — expected for ${ARCH}/${OS}/JDK${MAJOR_VERSION}"`

### Relevant Context

- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:591) —
  `verify_glibc_version()` — the function to change. The `expected_glibc="2.2.5"` line is
  at approximately line 605.
- [`tooling/validateSBOMcontent.sh`](tooling/validateSBOMcontent.sh:53) — the source of
  truth for GLIBC expected values (lines 55–75).

### Status
[x] done — REVISED: per-arch devkit GLIBC version (2.12/2.17/2.23/2.27) does NOT appear
as a readable string in the java launcher binary (confirmed via readelf -V and strings on
JDK 17/21/25 Temurin binaries — only GLIBC_2.2.5 is present regardless of devkit). The
GLIBC check reverted to the GLIBC_2.2.5 sentinel which confirms glibc-linkage only. Per-arch
devkit version checking remains the responsibility of validateSBOMcontent.sh via SBOM metadata.

---

## Sub-Task 2 — Broaden Compiler Check to Cover AIX and macOS

### Intent

`verify_gcc_version()` currently skips AIX and macOS with a `print_info "Skipping"` message
and returns. With every stage now running on a native host, it is both possible and
desirable to verify the compiler toolchain on those platforms too.

**AIX:** `validateSBOMcontent.sh` lines 44–49 define the expected compiler as:
- `xlc (IBM XL C/C++)` for `MAJOR_VERSION <= 21`
- `clang (clang/LLVM)` for `MAJOR_VERSION > 21`

The `strings` command on AIX works on the shared library `libjvm.so` or the `java`
executable. The XLC compiler embeds a version string of the form `IBM XL C/C++ for AIX`
and clang embeds a `clang version X.Y.Z` string. The check should look for the presence
of either the `IBM XL` or `clang version` token as appropriate.

**macOS:** `validateSBOMcontent.sh` lines 82–88 define the expected compiler as:
- `clang (clang/LLVM from Xcode 15.2)` for JDK ≥ 9 (all non-JDK8 builds)
- `clang (clang/LLVM)` for JDK 8 x64

macOS binaries embed a clang version string visible via `strings`. The `java` binary in
a Temurin macOS tarball (`.tar.gz`) contains `LLVM` and/or `clang version` tokens. The
check should look for `clang` in the strings output and the Xcode version string where
applicable.

**Windows:** Windows PE binaries do not embed GCC/clang/MSVC version strings in a format
reliably extractable by the POSIX `strings` command available on a standard shell Jenkins
agent. No strings-based compiler check is feasible for Windows. The `-b` flag is retained
for Windows stages and the function continues to return early for `windows`.

**Rename:** Because the function now covers GCC, clang, and XLC — not just GCC — it should
be renamed `verify_compiler_version()` to accurately describe its scope. All call sites and
comments must be updated.

### Expected Outcomes

- The function is renamed from `verify_gcc_version()` to `verify_compiler_version()`.
- All call sites in the main body and all comments referencing the old name are updated.
- For `OS=aix`:
  - When `MAJOR_VERSION <= 21`: check that `strings tarballtest/bin/java` contains `IBM XL`
    (the XLC compiler marker).
  - When `MAJOR_VERSION > 21`: check that `strings tarballtest/bin/java` contains
    `clang version` (the clang/LLVM marker).
  - On failure: `print_error` and set `RC=4`.
  - On pass: `print_pass "Compiler: XLC / clang (AIX)"` as appropriate.
- For `OS=mac`:
  - Check that `strings tarballtest/bin/java` contains `clang`.
  - On failure: `print_error` and set `RC=4`.
  - On pass: `print_pass "Compiler: clang (macOS)"`.
- `windows` still returns early with a `print_verbose` skip message (no change).
- All existing GCC and Alpine/riscv64 checks are unchanged in logic.
- The existing JRE tarball presence guard (`ls OpenJDK*-jre_...`) is retained at the top.
- The unit test file does not test `verify_compiler_version()` directly (it requires a real
  binary); the rename must be reflected in any comments in the test file that reference the
  old name.

### Todo List

1. In `release_download_test_new.sh`, rename the function from `verify_gcc_version()` to
   `verify_compiler_version()`.
2. Update the call site in the main body (`verify_gcc_version` → `verify_compiler_version`).
3. Update the function's header comment block to describe the broader scope including AIX
   and macOS.
4. Replace the `case "${OS}" in mac|windows|aix)` early-return block with a block that
   only returns early for `windows`.
5. Add an `aix` branch after the `windows` early-return: implement the `MAJOR_VERSION`-
   conditional check for `IBM XL` vs `clang version` strings, with appropriate `print_error`
   / `print_pass` / `RC=4` handling.
6. Add a `mac` branch in the OS dispatch (after the `alpine-linux` / `riscv64` / glibc
   Linux branches): implement the `clang` string check, with appropriate `print_error` /
   `print_pass` / `RC=4` handling.
7. Update the `_PHASE_BINARIES` tracking comment in the main body if it references the old
   function name.
8. Check `unit_tests/test_release_download.sh` for any references to `verify_gcc_version`
   and update them to `verify_compiler_version` if present.

### Relevant Context

- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:627) —
  `verify_gcc_version()` to rename and extend.
- [`tooling/validateSBOMcontent.sh`](tooling/validateSBOMcontent.sh:44) — compiler
  expectations for AIX (lines 44–49) and macOS (lines 82–88).
- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:831) —
  main body call site `verify_gcc_version`.

### Status
[x] done

---

## Sub-Task 3 — Simplify Output: Verbose-Gate All Intermediate Progress

### Intent

In the current script, `print_section()`, `print_info()`, and `print_pass()` are always
printed regardless of the `-v` flag. With 13 parallel Jenkins stages each producing
hundreds of lines, this creates an unusable wall of output. The required behaviour is:

- **Normal mode** (no `-v`): print only `ERROR:` lines (from `print_error`) and the final
  summary table (from `print_summary`). Nothing else.
- **Verbose mode** (`-v`): print all section banners, info lines, per-item PASS lines, and
  the existing verbose trace.

This is a pure output change — no logic changes to validation results, exit codes, or phase
tracking variables.

### Expected Outcomes

- `print_section()`, `print_info()`, and `print_pass()` all become verbose-gated: they only
  emit output when `VERBOSE=true`.
- `print_error()` (sourced from `common_logging.sh`) is always printed — it must not be
  gated.
- `print_summary()` is always printed — it must not be gated.
- The startup context line (`tag=... version=... arch=... os=...`) in the main body is
  moved inside a `print_verbose` call so it is suppressed in normal mode.
- The `download_count` summary line in `download_release_files()` is verbose-gated.
- The `ls -l` debug listing line in the main body (already guarded by `[ "$VERBOSE" = "true" ]`) is unchanged.
- The Jenkins Jenkinsfile `sh` invocation already passes `-v -a` to the script — this
  remains correct since verbose mode is still available; the change is to what the default
  (non-verbose) mode shows.
- The unit test file requires no changes (it tests logic functions, not output).

### Todo List

1. In `print_section()`, wrap the `echo` with `if [ "$VERBOSE" = "true" ]; then ... fi`
   (or equivalent guard pattern matching `print_verbose`).
2. In `print_info()`, apply the same verbose guard.
3. In `print_pass()`, apply the same verbose guard.
4. In the main body, change the `print_section "Release Download Validation starting"` and
   `print_info "tag=..."` context line calls to `print_verbose` so they are suppressed in
   normal mode.
5. In `download_release_files()`, change the `print_info "Finished downloads — ..."` line
   to `print_verbose`.
6. In `import_gpg_key()`, the `print_info "GPG key imported and trusted"` line should
   become `print_verbose`.
7. Verify `print_summary()` is not wrapped in any verbose guard — it must always execute.

### Relevant Context

- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:145) —
  `print_section()` definition.
- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:154) —
  `print_info()` definition.
- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:163) —
  `print_pass()` definition.
- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:727) —
  `print_summary()` definition — must remain always-printed.
- [`tooling/release_download_test/release_download_test_new.sh`](tooling/release_download_test/release_download_test_new.sh:800) —
  main body startup section and context line.

### Status
[x] done

---

## Sub-Task 4 — Rewrite Jenkinsfile Node Labels to AQA Standard and Enable Native Binary Checks

### Intent

Two changes are needed in the Jenkinsfile:

**Node labels:** The current labels use the `ci-jenkins-pipelines` compound format
(`build&&linux&&x64&&dockerBuild&&dynamicAzure`). These must be replaced with the AQA-test
standard used across the Adoptium test infrastructure, confirmed from
`aqa-tests/buildenv/jenkins/openjdk_tests`. The format is
`ci.role.test&&hw.arch.<arch>&&sw.os.<os>` with the following arch token mapping
(confirmed directly from the AQA PLATFORM_MAP):

| Temurin arch | AQA hw.arch token |
|-------------|------------------|
| x64         | x86              |
| aarch64     | aarch64          |
| s390x       | s390x            |
| ppc64le     | ppc64le          |
| ppc64       | ppc64            |
| arm (arm32) | aarch32          |
| riscv64     | riscv            |

OS tokens: `sw.os.linux`, `sw.os.windows`, `sw.os.aix`, `sw.os.alpine-linux`.
macOS uses `(sw.os.osx||sw.os.mac)` per the AQA convention.

**Native binary checks on every arch:** Every stage now runs on a host of the correct
architecture and OS. The script (after Sub-Tasks 1 and 2) can perform `java -version`,
GLIBC, and compiler checks on every platform natively. The `-b` flag should only be passed
to stages where no meaningful binary check is possible:
- `windows`: MSVC PE binaries do not embed compiler version strings extractable by POSIX
  `strings`; binary checks remain skipped.
- All other stages: no `-b` flag. The script internally handles the per-OS logic (AIX XLC/
  clang, macOS clang, Alpine GCC, glibc Linux GCC/GLIBC).

The Jenkinsfile `sh` call should pass `-a` (ANSI) but **not** `-v` (verbose) so that
normal mode (silent except errors and summary, per Sub-Task 3) is used by default in
Jenkins. Verbose mode is available via a new pipeline boolean parameter.

### Expected Outcomes

- All 13 stages in the `stages` map have their `nodeLabel` updated to AQA-format labels.
- The `-b` flag is removed from all stages except `x64-windows` and `aarch64-windows`.
- `ppc64-aix` has `-b` removed — the script now handles AIX compiler checks via
  `verify_compiler_version()` (Sub-Task 2).
- A new `booleanParam` named `VERBOSE` (default `false`) is added to the `parameters`
  block.
- The `sh` command passes `-a` always, and conditionally appends `-v` when
  `params.VERBOSE` is true.
- The header comment block is updated to reflect the AQA label convention, native checks
  on all platforms, and the new VERBOSE parameter.

### Stage Label Table (final state after this sub-task)

| Stage name             | AQA node label                                             | Flags                   |
|------------------------|------------------------------------------------------------|-------------------------|
| `x64-linux`            | `ci.role.test&&hw.arch.x86&&sw.os.linux`                   | `-A x64 -O linux`       |
| `aarch64-linux`        | `ci.role.test&&hw.arch.aarch64&&sw.os.linux`               | `-A aarch64 -O linux`   |
| `x64-alpine-linux`     | `ci.role.test&&hw.arch.x86&&sw.os.alpine-linux`            | `-A x64 -O alpine-linux` |
| `aarch64-alpine-linux` | `ci.role.test&&hw.arch.aarch64&&sw.os.alpine-linux`        | `-A aarch64 -O alpine-linux` |
| `x64-mac`              | `ci.role.test&&hw.arch.x86&&(sw.os.osx\|\|sw.os.mac)`      | `-A x64 -O mac`         |
| `aarch64-mac`          | `ci.role.test&&hw.arch.aarch64&&(sw.os.osx\|\|sw.os.mac)`  | `-A aarch64 -O mac`     |
| `s390x-linux`          | `ci.role.test&&hw.arch.s390x&&sw.os.linux`                 | `-A s390x -O linux`     |
| `ppc64le-linux`        | `ci.role.test&&hw.arch.ppc64le&&sw.os.linux`               | `-A ppc64le -O linux`   |
| `ppc64-aix`            | `ci.role.test&&hw.arch.ppc64&&sw.os.aix`                   | `-A ppc64 -O aix`       |
| `riscv64-linux`        | `ci.role.test&&hw.arch.riscv&&sw.os.linux`                 | `-A riscv64 -O linux`   |
| `arm-linux`            | `ci.role.test&&hw.arch.aarch32&&sw.os.linux`               | `-A arm -O linux`       |
| `x64-windows`          | `ci.role.test&&hw.arch.x86&&sw.os.windows`                 | `-A x64 -O windows -b`  |
| `aarch64-windows`      | `ci.role.test&&hw.arch.aarch64&&sw.os.windows`             | `-A aarch64 -O windows -b` |

### Todo List

1. In `Jenkinsfile.release_download_test`, update the `stages` map: replace every
   `nodeLabel` value with the AQA-format label from the table above.
2. Remove the `-b` flag from the `extraFlags` for all stages except `x64-windows` and
   `aarch64-windows`.
3. Add a `booleanParam` named `VERBOSE` with `defaultValue: false` and description:
   "Enable full per-file validation logging (-v flag). Off by default; enable to diagnose failures."
4. In the `script` block, define `def verboseFlag = params.VERBOSE ? '-v' : ''` before
   the `stages.each` loop.
5. Update the `sh` command from `bash ... -v -a ${extraFlags}` to
   `bash ... -a ${verboseFlag} ${extraFlags}`.
6. Update the header comment to reflect: AQA label scheme, native checks on all platforms,
   Windows-only `-b`, and the VERBOSE parameter.

### Relevant Context

- [`tooling/release_download_test/Jenkinsfile.release_download_test`](tooling/release_download_test/Jenkinsfile.release_download_test:65) —
  the `stages` map to replace (lines 65–84).
- [`tooling/release_download_test/Jenkinsfile.release_download_test`](tooling/release_download_test/Jenkinsfile.release_download_test:44) —
  `parameters` block to extend with `VERBOSE`.
- [`tooling/release_download_test/Jenkinsfile.release_download_test`](tooling/release_download_test/Jenkinsfile.release_download_test:107) —
  the `sh` command to update.
- AQA label source of truth confirmed from `aqa-tests/buildenv/jenkins/openjdk_tests`:
  `hw.arch.x86` for x64, `hw.arch.riscv` for riscv64, `hw.arch.aarch32` for arm,
  `(sw.os.osx||sw.os.mac)` for macOS.

### Status
[x] done
