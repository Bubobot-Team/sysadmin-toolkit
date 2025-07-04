# SSL Health Assessment Tool

This directory contains a comprehensive SSL/TLS security scanner for assessing SSL certificate health and security.

## Tool

### SSL Health Assessment (`ssl-health-assessment.js`)

A comprehensive SSL/TLS security scanner that analyzes:
- Certificate chain validation
- Protocol support (TLS 1.0-1.3, SSL 2/3)
- Security vulnerabilities
- Compliance scoring
- Performance metrics

**Usage:**
```bash
node ssl-health-assessment.js <hostname> [port]
```

**Example:**
```bash
node ssl-health-assessment.js google.com 443
```

**Features:**
- ✅ Connection testing with proper error handling
- ✅ Certificate analysis and expiry checking
- ✅ Protocol support detection
- ✅ Vulnerability scanning (POODLE, FREAK, etc.)
- ✅ Security grading (A+ to F)
- ✅ Detailed recommendations
- ✅ JSON report generation

## Common SSL Issues & Solutions

### 1. Certificate Chain Issues

**Problem:** `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`

**Solution:** Ensure complete certificate chain:
```bash
# Create fullchain.pem with proper order:
# 1. Server certificate
# 2. Intermediate certificate  
# 3. Root certificate
cat server.crt intermediate.crt root.crt > fullchain.pem
```

### 2. Self-Signed Certificates

**Problem:** `DEPTH_ZERO_SELF_SIGNED_CERT`

**Solutions:**
- Use certificates from trusted CAs for production
- Add custom CA to Node.js trust store:
```bash
export NODE_EXTRA_CA_CERTS=/path/to/ca-certs.pem
node your-app.js
```

### 3. Expired Certificates

**Problem:** `CERT_HAS_EXPIRED`

**Solution:** Renew SSL certificate before expiry

### 4. Missing Intermediate Certificates

**Problem:** `UNABLE_TO_VERIFY_LEAF_SIGNATURE`

**Solution:** Include intermediate certificates in the chain

## Node.js SSL Configuration

### Environment Variables

```bash
# Add custom CA certificates
export NODE_EXTRA_CA_CERTS=/path/to/ca-certs.pem

# Disable SSL verification (development only)
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

### Code Configuration

```javascript
const https = require('https');

const options = {
    hostname: 'example.com',
    port: 443,
    path: '/',
    method: 'GET',
    rejectUnauthorized: false, // Disables SSL verification
    ca: fs.readFileSync('/path/to/ca-certs.pem'), // Custom CA
    cert: fs.readFileSync('/path/to/client-cert.pem'), // Client certificate
    key: fs.readFileSync('/path/to/client-key.pem') // Client private key
};
```

## Best Practices

1. **Always use complete certificate chains**
2. **Keep certificates up to date**
3. **Use trusted CAs for production**
4. **Monitor certificate expiry dates**
5. **Test SSL configuration regularly**
6. **Use proper error handling**
7. **Avoid disabling SSL verification in production**

## Security Considerations

- Never disable SSL verification in production
- Keep Node.js and dependencies updated
- Use strong cipher suites
- Implement proper certificate validation
- Monitor for security vulnerabilities

## References

- [Node.js TLS Documentation](https://nodejs.org/api/tls.html)
- [SSL Labs Test](https://www.ssllabs.com/ssltest/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Let's Encrypt](https://letsencrypt.org/)

## Troubleshooting Tips

1. **Check certificate expiry:**
   ```bash
   openssl x509 -in certificate.crt -text -noout | grep -A 2 "Validity"
   ```

2. **Verify certificate chain:**
   ```bash
   openssl s_client -connect example.com:443 -showcerts
   ```

3. **Test specific protocols:**
   ```bash
   openssl s_client -connect example.com:443 -tls1_2
   ```

4. **Check cipher suites:**
   ```bash
   openssl ciphers -v
   ```

## Report Files

The tool generates JSON reports with timestamps:
- `ssl-report-{hostname}-{timestamp}.json`

These reports contain detailed analysis results and can be used for:
- Security audits
- Compliance reporting
- Trend analysis
- Documentation 