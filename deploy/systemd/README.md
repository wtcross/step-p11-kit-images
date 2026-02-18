# Systemd (Quadlet)

This directory contains rootless user-mode units for running `step-ca-p11-kit` with p11-kit and Podman.

## Unit Layout

Install these files in your user config:

- `~/.config/containers/systemd/`:
  - `step-ca-p11-kit@.container`
  - `step-ca-p11-kit.network`
  - `step-ca-p11-kit@.volume`
- `~/.config/systemd/user/`:
  - `step-ca-p11-kit@.target`
  - `p11-kit-server@.service`
  - `p11-kit-server@.socket`
  - `p11-kit-server@.target`

## Production Flow (per instance)

1. Generate env files:

```
./scripts/generate-instance-env.sh \
  --instance prod \
  --ca-name "Example CA" \
  --dns "ca.example.local" \
  --external-port 9443 \
  --hsm-uri "pkcs11:token=RootCA" \
  --private-key-pkcs11-uri "pkcs11:token=IntermediateCA;id=%01;object=intermediate;type=private?module-path=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so&pin-source=file:///run/secrets/hsm-pin" \
  --kms-pkcs11-uri "pkcs11:token=IntermediateCA?module-path=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so&pin-source=file:///run/secrets/hsm-pin"
```

This writes:
- `%h/.config/p11-kit-server/prod.env`
- `%h/.config/step-ca/prod.env`
- `%h/.config/containers/systemd/step-ca-p11-kit@prod.container.d/10-publish-port.conf`

2. Create required Podman secrets for the instance:

```
podman secret create hsm-pin-prod /path/to/hsm-pin
podman secret create admin-password-prod /path/to/admin-password
podman secret create root-cert-prod /path/to/root.crt
podman secret create intermediate-cert-prod /path/to/intermediate.crt
```

3. Start services:

```
systemctl --user daemon-reload
systemctl --user enable --now p11-kit-server@prod.target
systemctl --user enable --now step-ca-p11-kit@prod.target
```

## Runtime Notes

- The PKCS#11 socket is created at `%t/p11-kit/<instance>.sock` and consumed inside the container as `/run/p11-kit/<instance>.sock`.
- `step-ca-p11-kit@.container` mounts instance-scoped Podman secrets to:
  - `/run/secrets/hsm-pin`
  - `/run/secrets/admin-password`
  - `/run/secrets/root.crt`
  - `/run/secrets/intermediate.crt`
- `step-ca-p11-kit@.container` uses `Pull=always` by default; use systemd drop-ins if you need different pull behavior.
- `step-ca-p11-kit@.container` runs `cosign verify` in `ExecStartPre` before startup; install `cosign` on the host and update both `Image=` and `ExecStartPre=` together when overriding the image reference.
- `scripts/generate-instance-env.sh` writes a per-instance drop-in with `PublishPort=<external>:9000` so the container always listens on internal port `9000` while the host port remains configurable.
