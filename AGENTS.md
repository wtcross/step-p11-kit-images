# AGENTS.md

## Purpose and Scope

This file defines contribution standards for the entire repository.

- Scope: applies to all files and directories in this repo unless a deeper scoped `AGENTS.md` adds stricter rules.
- Goal: keep image builds, PKCS#11 behavior, deployment assets, and tests consistent and reproducible.

## Repository Layout

- `deploy/`: deployment-related assets. Currently systemd/quadlet unit files and docs.
- `images/`: one directory per container image (`Containerfile`, image entrypoint/scripts, image README).
- `scripts/`: host/build/test helper scripts.
- `scripts/common/`: reusable shell modules shared across host scripts and image entrypoints.
- `tests/`: all tests and test helpers.
  - `tests/helpers/`: BATS helper libraries.
  - `tests/unit/`: BATS unit tests (especially for `scripts/common` modules).
  - `tests/functional/`: BATS functional tests for image runtime behavior.

## Code Reuse

Reuse `scripts/common` whenever possible.

- Before adding new shell logic to image scripts or top-level scripts, check `scripts/common/*.sh`.
- Prefer extending existing shared modules (`validation.sh`, `logging.sh`, `pkcs11.sh`, `openssl.sh`) over duplicating logic.
- New reusable behavior must be implemented in `scripts/common` and covered by unit tests in `tests/unit/common`.

## Dependency and Version Management

`versions.env` is the single source of truth for pinned dependency versions and base image digests.

- Keep dependency versions/digests in the authoritative `versions.env` file
- All images that use a dependency from `versions.env` must use the same specified version
- `Makefile` passes those values as build args; do not hardcode drifting versions in image definitions.
- If a dependency version changes, update `versions.env` and run tests (`make test` at minimum).
- Keep image tags and references in sync with existing build targets in `Makefile`.

## Code Style and Shell Conventions

Formatting follows `.editorconfig`.

- Ensure generated/edited files conform to `.editorconfig` rules.
- Bash scripts should use:
  - `#!/usr/bin/env bash`
  - `set -o errexit`
  - `set -o nounset`
  - `set -o pipefail`
- Use shared logging/validation helpers where available (`log_*`, `require_*`).
- Keep shell sourcing ShellCheck-friendly using `# shellcheck source=...` comments where needed.
- Keep scripts readable and defensive: quote variables, validate required inputs early, fail fast.

## Containerfile Standards

- Pin base images by digest where practical.
- Install packages with `--no-install-recommends` and clean apt metadata/lists after install.
- Prefer minimal runtime dependencies and non-root runtime users where feasible.
- Copy shared shell modules from `scripts/common` instead of duplicating script code between images.

## Supply Chain and Artifact Verification

Anything pulled from a GitHub release must be verified with Cosign before use.

- Verify artifacts before install/extract/build steps.
- For container image provenance/signing flows, prefer digest-based operations and verification.
- New external artifacts/dependencies must include a verification approach that matches current project standards.

## p11-kit Version Compatibility

Host/server-side and client/container-side `p11-kit` versions must be identical.

- `P11_KIT_VERSION` in `versions.env` is authoritative.
- All images that install `p11-kit` must consume the same pinned version.
- Any change to p11-kit versioning or PKCS#11 transport behavior must be validated with functional tests and systemd testing.
- The `p11-kit` must be the same on both ends of the RPC connection used by `p11-kit server` and `p11-kit-client.so`

## Testing and CI Expectations

- For behavior changes, run `make test`.
- For systemd/quadlet/deployment-path changes, also run `make run-systemd-testing`.
- New or changed shared shell behavior should include/adjust unit tests under `tests/unit/common`.
- Keep GitHub Actions workflows (`tests`, `build-scan`, `sign`) passing with your changes.

## Change Hygiene

- Keep changes scoped and intentional.
- Update relevant documentation when behavior, required environment variables, build inputs, or deployment steps change.
- Do not introduce duplicate shell logic when shared modules can be extended.
- Preserve backward-compatible behavior unless a breaking change is explicitly intended and documented.
