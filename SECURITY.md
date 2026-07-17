# Security Policy

## Reporting a vulnerability

Report suspected vulnerabilities privately to:

`dmitrijs.brujevs@gmail.com`

Do not create a public issue or disclose the vulnerability before receiving
authorization.

Include the affected version, reproduction steps, expected and observed impact,
and relevant logs with credentials removed.

## Sensitive data

Never include these items in issues, logs, tests, or commits:

- GitHub personal access tokens;
- private repository contents;
- Docker TLS credentials;
- application or server secrets;
- production environment files.

## Security boundaries

This bootstrap temporarily receives a fine-grained GitHub token with read-only
Contents access to `db-web-solutions/docker-platform`. It must not persist the
token, pass it through `sudo`, expose it in process arguments, or print it.

The bootstrap validates transport success and archive structure. The private
Docker Platform installation engine remains responsible for release-content
validation, filesystem safety, immutable installation, and atomic activation.

The bootstrap does not install Docker, configure a firewall, prepare a server,
initialize Docker Platform, or start its runtime.

## Supported versions

Only the latest published stable installer release is supported. Older releases
may be used for reproducibility but should be upgraded when security fixes are
published.
