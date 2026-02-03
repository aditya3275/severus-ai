# App-Level Config for mTLS

Once the certificates are mounted via Helm, you need to update your application to use them for secure communication.

## Environment Variables
The following environment variables are automatically injected by the updated `deployment.yaml`:

- `TLS_CERT_PATH`: `/etc/tls/tls.crt`
- `TLS_KEY_PATH`: `/etc/tls/tls.key`
- `CA_CERT_PATH`: `/etc/tls/ca.crt`

## Python Example (requests)
To make a secure call to another service using these certificates:

```python
import os
import requests

def get_secure_session():
    session = requests.Session()
    session.cert = (os.getenv('TLS_CERT_PATH'), os.getenv('TLS_KEY_PATH'))
    session.verify = os.getenv('CA_CERT_PATH')
    return session

# Usage
session = get_secure_session()
response = session.get('https://other-service.svc.cluster.local')
```

## Python Example (Built-in ssl)
For a server-side implementation using standard libraries:

```python
import ssl
import os

context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
context.load_cert_chain(
    certfile=os.getenv('TLS_CERT_PATH'), 
    keyfile=os.getenv('TLS_KEY_PATH')
)
context.load_verify_locations(cafile=os.getenv('CA_CERT_PATH'))
context.verify_mode = ssl.CERT_REQUIRED
```
