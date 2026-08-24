# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's
private vulnerability reporting feature in the repository's **Security** tab.

Include the affected Lokalweb version, macOS version, reproduction steps,
impact and any relevant logs with credentials and local paths removed.

## Security boundary

Lokalweb launches local development runtimes and writes configuration files.
It must only stop processes verified as Lokalweb-owned. Reports involving
unexpected process termination, command execution, path traversal, credential
exposure, unsafe database replacement or unintended non-loopback access are
especially important.
