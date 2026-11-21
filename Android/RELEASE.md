# Android release candidate

The Android VPN integration is not yet validated on a physical device. Do not
promote a candidate to a public release until VPN consent, real traffic, DNS,
revoke, reconnect, install and upgrade have been tested on supported Android
versions and the bundled upstream licensing conditions have been reviewed.
Android versions below 29 currently fail closed at traffic verification.

The manually dispatched **Android signed release candidate** GitHub Actions
workflow tests and builds the app with the verified 5.9.11 mobile engine, then
checks its signature and uploads a candidate and SHA-256 checksum as a temporary
workflow artifact. It does not publish a GitHub release. Configure these GitHub
Actions secrets in the repository settings (never send their values in chat):

- `UMBRELLA_ANDROID_KEYSTORE_BASE64`: base64 of the owner's persistent release keystore.
- `UMBRELLA_ANDROID_STORE_PASSWORD`: keystore password.
- `UMBRELLA_ANDROID_KEY_ALIAS`: release key alias.
- `UMBRELLA_ANDROID_KEY_PASSWORD`: release key password.

The owner must retain and back up the same signing key securely; Android upgrades
require a compatible signing identity. Do not use a debug key or a throwaway CI
key for distribution. Local builds use the same names as environment variables,
except `UMBRELLA_ANDROID_KEYSTORE` is the absolute path to the keystore file.
The CI debug APK and its disposable-key release test are not upgrade-compatible
with a production-signed APK.

After testing a candidate, record the device models, Android versions, APK
checksum, certificate fingerprint and test outcomes. The current workflow does
not claim that successful compilation proves a functioning VPN.
