# Release Download Jenkinsfile Parameter Update Plan

## Top-Level Overview
Add two pipeline parameters to [`tooling/release_download_test/Jenkinsfile`](tooling/release_download_test/Jenkinsfile) so the job can be pointed at a fork and branch outside the default repository branch, and set the Jenkins build display name to show the selected release tag and branch. The scope is intentionally limited to the parameter surface and display naming only; SCM job configuration changes remain external to this repository.

## Sub-Tasks

### 1. Add fork selection parameters
- **Intent** — Expose the repository fork and branch as pipeline parameters so Jenkins job configuration can consume them for independent script development and testing.
- **Expected Outcomes** — The pipeline defines `FORK` and `BRANCH` parameters, with defaults of `adoptium` and `master`, alongside the existing parameters.
- **Todo List**
  1. Update the parameter block in [`tooling/release_download_test/Jenkinsfile`](tooling/release_download_test/Jenkinsfile) to add `FORK`.
  2. Update the same block to add `BRANCH`.
  3. Keep existing parameter behavior unchanged.
- **Relevant Context** — Existing parameter definitions are in [`tooling/release_download_test/Jenkinsfile`](tooling/release_download_test/Jenkinsfile).
- **Status** — [x] done

### 2. Set the build display name from tag and branch
- **Intent** — Make Jenkins runs easier to identify by showing the selected release tag and branch in the build display name.
- **Expected Outcomes** — Early in pipeline execution, the build display name is set to `${TAG} (${BRANCH})` using the pipeline parameters.
- **Todo List**
  1. Add a display name assignment in the first available script execution path of [`tooling/release_download_test/Jenkinsfile`](tooling/release_download_test/Jenkinsfile).
  2. Use the existing parameter access pattern so the display name is derived from `params.TAG` and `params.BRANCH`.
  3. Avoid changing stage logic, checkout steps, or summary behavior.
- **Relevant Context** — The first stage script block begins in [`tooling/release_download_test/Jenkinsfile`](tooling/release_download_test/Jenkinsfile).
- **Status** — [x] done

---

## Test Run Results

### jdk-27+9-ea-beta — 2025-07-31

| Platform | GPG | Archive | SBOM | Binary |
|---|---|---|---|---|
| x64/linux | N/A | N/A | N/A | PASS |
| aarch64/linux | N/A | N/A | N/A | PASS |
| x64/alpine-linux | N/A | N/A | N/A | PASS |
| aarch64/alpine-linux | N/A | N/A | N/A | PASS |
| x64/mac | N/A | N/A | N/A | PASS |
| aarch64/mac | N/A | N/A | N/A | PASS |
| s390x/linux | N/A | N/A | N/A | PASS |
| ppc64le/linux | N/A | N/A | N/A | PASS |
| ppc64/aix | N/A | N/A | N/A | PASS |
| riscv64/linux | N/A | N/A | N/A | PASS |
| arm/linux | N/A | N/A | N/A | SKIP-VER _(not released for JDK 27, valid range: 8–20)_ |
| x64/windows | N/A | N/A | N/A | PASS |
| aarch64/windows | N/A | N/A | N/A | PASS |

**Overall: PASS**

> GPG/Archive/SBOM show N/A on arch-node rows because those checks run centrally (Stage 1) and result files were not propagated to the Summary stage in this run.
