# softhsm2-p11-kit

Runs a `p11-kit server` exposing a PKCS#11 socket for use in testing other images in this repo.

## Environment Variables

Required:
- `ROOT_CA_PKCS11_TOKEN_LABEL`: PKCS#11 token label of the slot to use for the root CA
- `STEP_CA_PKCS11_TOKEN_LABEL`: PKCS#11 token label of the slot to use for the step-ca instance

Optional:
- `STEP_HSM_PIN_FILE_PATH` (default `/run/secrets/hsm-pin`)
- `SOFTHSM_LIB_PATH` (default `/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so`)
- `STEP_P11KIT_SOCKET_PATH` (default `/run/p11-kit/pkcs11-socket`)
- `P11_KIT_SOCKET` (legacy alias of `STEP_P11KIT_SOCKET_PATH`)
- `SOFTHSM_TOKEN_DIR` (default `/var/lib/softhsm/tokens`)
- `SOFTHSM2_CONF` (default `/etc/softhsm/softhsm2.conf`)

## Required Mounts

- `/run/p11-kit` (read/write)
- `/run/secrets` (must contain `hsm-pin`)

The image bundles reusable shell modules at `/usr/local/share/step-p11-kit`.

## Example running directly with podman for testing

```
podman run \
  --rm -it --pull=never \
  --security-opt label=disable \
  -e STEP_HSM_PIN_FILE_PATH="/run/secrets/hsm-pin" \
  -e STEP_P11KIT_SOCKET_PATH="/run/p11-kit/pkcs11-socket" \
  -e ROOT_CA_PKCS11_TOKEN_LABEL="RootCA" \
  -e STEP_CA_PKCS11_TOKEN_LABEL="IssuingCA" \
  -v ./secrets:/run/secrets:ro,z \
  -v ./p11-kit:/run/p11-kit:z \
  ghcr.io/wtcross/softhsm2-p11-kit:latest
```
