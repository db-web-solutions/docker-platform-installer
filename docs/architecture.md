# Installer Architecture

## Purpose

`docker-platform-installer` is the public authentication and download boundary
for the private `db-web-solutions/docker-platform` repository.

It solves one problem: provide a stable one-command entry point without making
the Docker Platform runtime repository public or duplicating its installation
logic.

## Components

The installation path has two independently versioned components:

1. Public bootstrap — this repository's tagged `install.sh`.
2. Private installation engine — the selected Docker Platform release's
   repository-root `install.sh`.

The public bootstrap owns authentication, immutable release selection,
authenticated downloads, transport-level validation, credential removal, and
privilege-boundary delegation.

The private engine owns release-content validation, system paths, immutable
release storage, atomic activation, reactivation, and rollback.

## Trust boundaries

```text
operator
  │ hidden token through /dev/tty
  ▼
public bootstrap
  │ authenticated HTTPS as normal user
  ▼
GitHub private repository
  │ exact-tag installer + matching archive
  ▼
validated temporary files
  │ token cleared; clean sudo environment
  ▼
private installation engine
  │ immutable release and atomic symlinks
  ▼
/opt/docker-platform + /usr/local/bin/docker-platform
```

The GitHub token never crosses the privilege boundary. The downloaded private
installer receives only a fixed `PATH`, the exact selected ref, and the local
archive path.

## Release selection

When `DOCKER_PLATFORM_REF` is set, only the exact
`vMAJOR.MINOR.PATCH` format is accepted.

When it is omitted, the bootstrap queries GitHub's latest-release endpoint and
accepts only a published, non-draft, non-prerelease release. The returned exact
tag is then used for both private downloads and private-engine delegation.

Branches, mutable aliases, partial versions, prerelease identifiers, and
arbitrary Git refs are rejected.

## Failure behavior

Before delegation, all downloads live in a mode-`0700` temporary directory.
Network, authentication, authorization, release-selection, installer, or
archive failures stop before privileged installation begins.

Temporary data is removed on success, ordinary failure, and handled signals.
After delegation begins, transactional filesystem behavior belongs to the
private installation engine.

## Explicit non-responsibilities

The public bootstrap does not:

- install or configure Docker;
- prepare the server or firewall;
- contain the Docker Platform CLI or Compose files;
- initialize or start the runtime;
- manage Docker mTLS;
- deploy application projects;
- store GitHub credentials;
- implement a second installation or rollback engine.
