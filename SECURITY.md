# Security Policy

## Reporting a Vulnerability

See [https://chef.io/security](https://chef.io/security) for our security policy and how to report a vulnerability.

## Secret Hygiene

- Do not commit private keys, tokens, kubeconfigs, cloud credentials, or local `.env` files.
- Use environment variables, secure secret stores, or local machine keychains for sensitive values.
- If a secret is found in a branch:
	- Remove the file/content from the branch immediately.
	- Rotate/revoke the exposed secret before merge.
	- Add or tighten ignore patterns to prevent recurrence.

### Common Sensitive File Types

- `*.pem`, `*.key`, `*.p12`, `*.pfx`
- `.env`, `.env.*`
- `id_rsa`, `id_rsa.*`
- `.aws/`, `.azure/`, `.gcp/`
