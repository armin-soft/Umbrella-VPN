# Encrypted application log export

The reports page can save the current application log as `.umbreport` using a user-supplied password. It is never uploaded automatically; users must send the file and password over separate trusted channels. It does not include raw core crash dumps, profiles, or all upstream diagnostics. The existing plaintext export remains available and should be shared only after review.

Format v1 is UTF-8 JSON: `format` = `umbrella-log-report-v1`, `kdf` = `PBKDF2-HMAC-SHA256`, `iterations` = 210000, `cipher` = `AES-256-GCM`; `salt` (16 bytes), `nonce` (12 bytes), `ciphertext`, and `tag` (16 bytes) are base64. The password's UTF-8 bytes are used unchanged. The associated data is UTF-8 `umbrella-log-report-v1`. For support staff, Python 3 with the `cryptography` package can decrypt it as follows; do not run this on an untrusted machine:

```python
import base64, getpass, json, sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
with open(sys.argv[1], encoding='utf-8') as f: d = json.load(f)
assert (d['format'], d['kdf'], d['iterations'], d['cipher']) == ('umbrella-log-report-v1', 'PBKDF2-HMAC-SHA256', 210000, 'AES-256-GCM')
b = lambda k: base64.b64decode(d[k], validate=True)
salt, nonce, tag, ciphertext = b('salt'), b('nonce'), b('tag'), b('ciphertext')
assert len(salt) == 16 and len(nonce) == 12 and len(tag) == 16 and len(ciphertext) <= 4 * 1024 * 1024
key = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=210000).derive(getpass.getpass('Password: ').encode('utf-8'))
print(AESGCM(key).decrypt(nonce, ciphertext + tag, b'umbrella-log-report-v1').decode('utf-8'))
```

The log is redacted best effort, not a guarantee that every possible secret or personal detail has been removed. The sender should inspect content and recipient before sharing. A lost password cannot be recovered. This is an independent format, not the upstream team's age-encrypted support bundle; no key has been provided for the Umbrella support team.
