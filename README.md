# step-p11-kit-images

Minimal container images and deployment assets for using [`step-ca`](https://github.com/smallstep/certificates) with PKCS#11 HSMs via [`p11-kit`](https://p11-glue.github.io/p11-glue/p11-kit.html).

> [!IMPORTANT]
> This project is a proof of concept and is not ready for production.

## Overview

The goal of this project is to simplify deployment of `step-ca` without requiring direct access to a PKCS#11 token. Instead, `step-ca` accesses the token via a PKCS#11 unix domain socket created by `p11-kit server`. It does this using the `p11-kit-client.so` PKCS#11 module. Other than security benefits, the nicest benefit to using `p11-kit server` is its capability to decouple the HSM and where `step-ca` is deployed through [PKCS#11 remoting](https://p11-glue.github.io/p11-glue/p11-kit/manual/remoting.html). Also, `p11-kit server` can expose multiple PKCS#11 tokens on the same socket as long as these tokens all belong to the same underlying module!

For now this project is intended to be deployed via rootless systemd quadlets.

The primary image in this repo is [`step-ca-p11-kit`](./images/step-ca-p11-kit/README.md). The [`deploy/systemd`](./deploy/systemd/README.md) directory contains systemd unit templates for setting up `p11-kit server` and running `step-ca-p11-kit` as a systemd quadlet on a host.

## Acknowledgements

I want to express gratitude to the Red Hat Security and Crypto Engineering teams (and other contributors) for the incredible open source work they do every day! Thank you 🙏❤️

## Future Work

- Ansible content collection for enabling easy deployment of `step-ca` with the systemd units in this project
- Kubernetes CSI for using PKCS#11 remoting via `p11-kit server`
- Investigate using [kryoptic](https://github.com/latchset/kryoptic) instead of SoftHSM2 for testing
- Investigate using [crypto-auditing](https://github.com/latchset/crypto-auditing) on the host system
- Investigate creating a quadlet for using kryoptic alongside `step-ca-p11-kit`

```text
+-----------------------------------------------------------------------------------------+
|                                    Host OS                                              |
|                                                                                         |
|                                       PKCS#11                                           |
|  +-------------------------+   some-pkcs11-module.so   +-----------------------------+  |
|  |          Token          | <-----------------------> |       p11-kit server        |  |
|  +-------------------------+                           |  (exports UNIX domain sock) |  |
|                                                        +--------------+--------------+  |
|                                                                   |                     |
|                                                                   |                     |
|                                                             pkcs11-socket               |
+-------------------------------------------------------------------|---------------------+
                                                                    |
                                                                    |
+-------------------------------------------------------------------|----------------------+
|                          Container: step-ca-p11-kit               |                      |
|                                                                   |                      |
|                                        PKCS#11                    v                      |
|  +-------------------------+      p11-kit-client.so       +----------------------------+ |
|  |        step-ca          | <--------------------------> | (mount)                    | |
|  |    (PKCS#11 client)     |                              | /run/p11-kit/pkcs11-socket | |
|  +-------------------------+                              +----------------------------+ |
|                                                                                          |
+------------------------------------------------------------------------------------------+
```

## Contents

- `images`: container images
- `deploy/systemd`: quadlet files and systemd user units for rootless deployments
- `scripts`: helper scripts for image builds, env generation, and test harness execution
- `scripts/common`: reusable shell modules shared by host scripts and image entrypoints
- `tests/helpers`: BATS helper scripts
- `tests/unit`: BATS-based unit tests for reusable shell modules
- `tests/functional`: BATS-based functional tests for image runtime behavior

## Supply Chain

Both the `step-ca` debian package and `step-cli` source artifacts are obtained from official github releases by Smallstep. Artifacts are verified using cosign.

## Quick Start (Local)

Reference the [`step-ca-p11-kit` README](./images/step-ca-p11-kit/README.md) for instructions on how to run a container locally. At a high level you need to run `p11-kit server` and mount the created socket (and other required mounts) and specify the required environment variables to run the container.

### Makefile Targets

1. Build images:

```bash
make build-all
```

2. Run all tests:

```bash
make test
```

Or run suites independently:

```bash
make test-unit
make test-functional
```

3. Run the portable systemd harness:

```bash
make run-systemd-testing
```

`make run-systemd-testing` builds the latest local images, saves local OCI archives under `.tmp/image-tars`, and runs the systemd-testing image using those local archives.

## License

[Apache License 2.0](./LICENSE)
