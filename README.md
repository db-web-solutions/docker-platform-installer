# Docker Platform Installer

Version metadata is maintained in [`VERSION`](VERSION).

This public repository contains the bootstrap downloader for the private
`db-web-solutions/docker-platform` project. It provides the official one-command
installation and update entrypoint without exposing or duplicating the private
runtime implementation.

The public `install.sh` authenticates to GitHub, selects an immutable release
tag, downloads the private installer and matching source archive, and delegates
the system installation to the private repository's own `install.sh`.

It does not contain the `docker-platform` CLI, Compose files, credentials,
deployment logic, server bootstrap logic, or a second installation engine.

The installer and Docker Platform have independent versions. The installer
version identifies this public bootstrap implementation; `DOCKER_PLATFORM_REF`
identifies the private platform release selected for installation.

## Documentation

- [Architecture and trust boundaries](docs/architecture.md)
- [Release process](docs/release-process.md)
- [Security policy](SECURITY.md)
- [Contributing and validation](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Requirements

The target must be Linux and provide:

- Bash;
- `curl`;
- `tar`;
- `mktemp`;
- `sudo`;
- an interactive `/dev/tty`.

The bootstrap does not install Docker or prepare a server.

## Install the latest stable release

Use a tagged release of this public bootstrap, never the mutable `main` branch:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/db-web-solutions/docker-platform-installer/v1.0.0/install.sh \
  | bash
```

The installer prompts for a GitHub token through `/dev/tty`, so the hidden
prompt works when the script itself is piped to Bash. GitHub's `latest` endpoint
is used only to discover the current published stable release. The resulting
exact tag, such as `v1.4.0`, is used for every subsequent download and for the
private installation engine.

Draft and prerelease releases are not selected by GitHub's latest-release API.

The bootstrap release in the URL is pinned independently from the private
Docker Platform release it discovers. Updating the public bootstrap therefore
never silently changes the downloaded bootstrap code.

## Install a specific release

Only a complete immutable tag in the form `vMAJOR.MINOR.PATCH` is accepted:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/db-web-solutions/docker-platform-installer/v1.0.0/install.sh \
  | DOCKER_PLATFORM_REF=v1.4.0 bash
```

Branches, `latest`, partial versions, prerelease versions, and arbitrary refs
are rejected.

## Update or reactivate

Run the latest-stable command again to update. Run the explicit-version command
to install or reactivate an older release.

The private installation engine owns idempotent reinstall, activation,
reactivation, and rollback behavior. Installing or changing the active release
does not automatically initialize, start, or restart the Docker Platform
runtime.

## Installer information

When working from a checkout, inspect the bootstrap without authentication or
system changes:

```bash
./install.sh --version
./install.sh --help
```

The version printed by `install.sh --version` must match the repository
`VERSION` file.

## Create the GitHub token

Create a fine-grained personal access token with only:

```text
Repository access:
  Only selected repositories
  db-web-solutions/docker-platform

Repository permissions:
  Contents: Read-only
```

No Actions, Administration, Secrets, Packages, or organization permissions are
required.

The token is entered at the hidden `/dev/tty` prompt. Do not put it in the
command line or an environment variable.

## Security model

- all GitHub traffic uses authenticated HTTPS;
- release selection resolves to an exact `vMAJOR.MINOR.PATCH` tag;
- the token is never passed in process arguments or to `sudo`;
- shell tracing is disabled before the token is read;
- the Authorization header is supplied to `curl` through standard input;
- API bodies and authenticated headers are never printed;
- downloads are staged as partial files and used only after successful HTTP
  completion;
- the private installer must be a non-empty regular file;
- the release archive must be a non-empty, valid `tar.gz`;
- the temporary directory has mode `0700`;
- the token is cleared before privilege escalation;
- temporary files are removed on success, failure, and signals;
- downloaded data is never evaluated or sourced by the bootstrap.

The private `install.sh` remains the sole owner of release-content validation,
system path safety, installation, and activation.

## Bootstrap workflow

The public bootstrap performs this fixed sequence:

```text
preflight
→ hidden GitHub authentication
→ private repository access check
→ exact release selection
→ private installer download
→ matching source archive download
→ archive validation
→ token removal
→ clean sudo environment
→ private installation engine
```

A failure before the final delegation does not modify the system installation.
The private engine performs its own release-content and activation validation
before changing the active release.

## Installation layout

The private installation engine creates:

```text
/opt/docker-platform/
├── current -> releases/<VERSION>
└── releases/
    └── <VERSION>/

/usr/local/bin/docker-platform
```

It preserves `/etc/docker-platform`, `/var/lib/docker-platform`, Docker volumes,
and application data.

## Continue

Confirm the installed CLI and explicitly initialize the intended environment:

```bash
docker-platform --version
sudo env ACME_EMAIL=admin@example.com docker-platform server init
sudo docker-platform server up
```

For a local-development installation, use `docker-platform local init`, install
the application TLS material, and then run `docker-platform local up`. Runtime
initialization and startup always remain separate explicit operations.

## Development and tests

Run the isolated shell test suite:

```bash
./tests/run.sh
```

The suite supplies mock GitHub API, `curl`, `sudo`, and private installer
implementations. It never contacts GitHub and does not need a real token or root
access. See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete validation
contract.

## License

This repository is proprietary. Use, modification, distribution, and
deployment require prior explicit written permission. See [LICENSE](LICENSE).
