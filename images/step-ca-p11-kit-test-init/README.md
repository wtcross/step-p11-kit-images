# step-ca-p11-kit-test-init

Use this image to initialize a 2-tier CA hierarchy for tests.

## Environment Variables

Required:
- `STEP_CA_NAME`: name of the Step CA-managed PKI
- `STEP_CA_DNS_NAMES`: comma-separated DNS names for the intermediate CA; first value is used as CN and all values are added as SANs
- `STEP_CA_ROOT_PRIVATE_KEY_PKCS11_URI`: full PKCS#11 URI of the root private key
- `STEP_CA_ROOT_CERT_NAME`: name of the cert to be created for the root CA
- `STEP_CA_INT_PRIVATE_KEY_PKCS11_URI`: full PKCS#11 URI of the intermediate private key
- `STEP_CA_INT_CERT_NAME`: name of the cert to be created for the intermediate CA

Optional:
- `STEPPATH` (default `/home/step/.step`)
- `STEP_OPENSSL_CONF_PATH` (default `/etc/ssl/openssl-pkcs11.cnf`)

Common runtime defaults:
- `STEP_HSM_PIN_FILE_PATH` (default `/run/secrets/hsm-pin`)
- `STEP_P11KIT_SOCKET_PATH` (default `/run/p11-kit/pkcs11-socket`)
- `STEP_P11KIT_CLIENT_MODULE_PATH` (default `/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so`)

Notes:
- Root certificate values remain static and represent an offline root CA.

## Required Mounts

- `/home/step/.step` (read/write)
- `/run/p11-kit` (must include a live p11-kit socket at `STEP_P11KIT_SOCKET_PATH`)
- `/run/secrets` (must include `hsm-pin`)

## Example running directly with podman for testing

```
podman run \
  --rm -it --pull=never \
  --security-opt label=disable \
  -e STEP_CA_NAME="Test CA" \
  -e STEP_CA_DNS_NAMES="ca.example.local,ca.internal.local" \
  -e STEP_HSM_PIN_FILE_PATH="/run/secrets/hsm-pin" \
  -e STEP_P11KIT_SOCKET_PATH="/run/p11-kit/pkcs11-socket" \
  -e STEP_CA_ROOT_PRIVATE_KEY_PKCS11_URI="pkcs11:token=RootCA;id=%01;object=root;type=private?module-path=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so&pin-source=file:///run/secrets/hsm-pin" \
  -e STEP_CA_ROOT_CERT_NAME="root.crt" \
  -e STEP_CA_INT_PRIVATE_KEY_PKCS11_URI="pkcs11:token=IntermediateCA;id=%01;object=intermediate;type=private?module-path=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so&pin-source=file:///run/secrets/hsm-pin" \
  -e STEP_CA_INT_CERT_NAME="intermediate.crt" \
  -v ./step:/home/step/.step:z \
  -v ./secrets:/run/secrets:ro,z \
  -v ./p11-kit:/run/p11-kit:z \
  ghcr.io/wtcross/step-ca-p11-kit-test-init:latest
```
