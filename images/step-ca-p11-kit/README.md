# step-ca-p11-kit

CGO-built `step-ca` image with PKCS#11 support via p11-kit. The image also
includes `step-cli` (`step`).

## Environment Variables

Required:
- `ROOT_CA_CERT_FILE`: path to the root certificate file
- `STEP_CA_NAME`: The name of the PKI
- `STEP_CA_DNS_NAMES`: Comma-separated list of DNS names for the CA
- `STEP_CA_PRIVATE_KEY_PKCS11_URI`: full PKCS#11 URI for the CA private key
- `STEP_CA_CERT_FILE`: path to the certificate file used by the step-ca instance
- `STEP_ADMIN_PASSWORD_FILE`: path to the admin password file

Optional:
- `STEP_CA_ADMIN_SUBJECT` (default `step`)
- `STEP_CA_ADMIN_PROVISIONER_NAME` (default `admin`)
- `STEP_CA_ADDRESS` (default `:9000`, must use internal port `9000`)
- `STEPPATH` (default `/home/step/.step`)

Common runtime defaults:
- `STEP_HSM_PIN_FILE_PATH` (default `/run/secrets/hsm-pin`)
- `STEP_P11KIT_SOCKET_PATH` (default `/run/p11-kit/pkcs11-socket`)
- `STEP_P11KIT_CLIENT_MODULE_PATH` (default `/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so`)

## Required Mounts

- `/home/step/.step` (read/write)
- `/run/p11-kit` (must include a live p11-kit socket at `STEP_P11KIT_SOCKET_PATH`)
- `/run/secrets` (must include `hsm-pin` and `admin-password`)

## Example running directly with podman for testing

```
podman run \
  --rm -it --pull=never \
  --security-opt label=disable \
  -p 9443:9000 \
  --add-host ca.example.local:127.0.0.1 \
  --add-host ca.internal.local:127.0.0.1 \
  -e STEP_CA_NAME="Test CA" \
  -e STEP_CA_DNS_NAMES="ca.example.local,ca.internal.local" \
  -e STEP_HSM_PIN_FILE_PATH="/run/secrets/hsm-pin" \
  -e STEP_P11KIT_SOCKET_PATH="/run/p11-kit/pkcs11-socket" \
  -e STEP_CA_PRIVATE_KEY_PKCS11_URI="pkcs11:token=IssuingCA;id=%01;object=issuing;type=private?module-path=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so&pin-source=file:///run/secrets/hsm-pin" \
  -e ROOT_CA_CERT_FILE="/home/step/.step/certs/root.crt" \
  -e STEP_CA_CERT_FILE="/home/step/.step/certs/ca.crt" \
  -e STEP_ADMIN_PASSWORD_FILE="/run/secrets/admin-password" \
  -v ./step:/home/step/.step:z \
  -v ./secrets:/run/secrets:ro,z \
  -v ./p11-kit:/run/p11-kit:z \
  ghcr.io/wtcross/step-ca-p11-kit:latest
```
