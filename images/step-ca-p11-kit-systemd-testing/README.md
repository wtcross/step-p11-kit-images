# step-ca-p11-kit-systemd-testing

Portable systemd test harness image for validating `deploy/systemd` units locally and in CI.

> [!NOTE]  
> I'm really not happy with this part of the project. I just needed a way to verify that the systemd units work as expected in a repeatable way. This is a vibe coded mess and will be cleaned up in the future.

## What It Does

At runtime, the harness:

1. Loads nested images from local OCI archives (`podman load`).
2. Starts user-level `p11-kit-server@<instance>.target`.
3. Runs `step-ca-p11-kit-test-init` to create root/issuing certs.
4. Starts `step-ca-p11-kit@<instance>.target`.
5. Runs `step ca health` against the running CA container.
6. Exits non-zero if health never passes.

## Usage

From the repo root:

```bash
make run-systemd-testing
```

This target:

- builds the latest local images,
- saves required local OCI archives,
- runs `scripts/run-systemd-testing-container.sh`.
