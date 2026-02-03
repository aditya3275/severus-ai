# TLS & mTLS Failure Scenarios

Understanding how certificate failures surface is critical for debugging.

## 1. Expired Certificate
**Symptom**: 
- Browser/Client: `SEC_ERROR_EXPIRED_CERTIFICATE` or "Your connection is not private".
- Ingress Controller (Traefik/Nginx): Logs show "Remote side closed connection" or similar handshake errors.

**Verification**:
```bash
kubectl get certificate
# Check 'NOT AFTER' column
kubectl describe certificate <name>
# Events will show "Certificate is expired"
```

## 2. Invalid or Untrusted Issuer
**Symptom**:
- `kubectl get certificate` shows `READY: False`.
- Ingress TLS handshake fails because the Secret is never created (or remains empty).

**Verification**:
```bash
kubectl get challenge # If using ACME/DNS-01
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
# Look for "Issuer not found" or "permission denied to reference secret"
```

## 3. mTLS Client Authentication Failure
**Symptom**:
- Application logs show `ssl.SSLCertVerificationError` or `requests.exceptions.SSLError`.
- Handshake fails with "alert certificate required".

**Debugging**:
1. Verify the client cert is mounted: `kubectl exec -it <pod> -- ls /etc/tls`
2. Check CA match: `openssl x509 -in /etc/tls/tls.crt -noout -issuer` vs `openssl x509 -in /etc/tls/ca.crt -noout -subject`

## 4. Misconfigured Ingress Annotation
**Symptom**:
- Ingress exists but is only serving HTTP.
- No `Certificate` resource is automatically created for the Ingress.

**Fix**:
Ensure `cert-manager.io/cluster-issuer` annotation matches the `ClusterIssuer` name exactly.
Check `cert-manager` logs for "Ingress update" events.
