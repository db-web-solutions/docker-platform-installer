# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Added the public Docker Platform bootstrap installer.
- Added interactive fine-grained GitHub token authentication through
  `/dev/tty`.
- Added automatic latest-stable discovery and exact
  `DOCKER_PLATFORM_REF=vMAJOR.MINOR.PATCH` selection.
- Added authenticated private installer and matching source archive downloads.
- Added token isolation, clean privilege escalation, archive validation, and
  temporary-file cleanup.
- Added isolated acceptance tests for authentication, release selection,
  downloads, cleanup, secret handling, delegation, and repeat execution.
- Added installer version/help output and repository `VERSION` metadata.
- Added architecture, release, contribution, security, licensing, and
  maintenance documentation.

[Unreleased]: https://github.com/db-web-solutions/docker-platform-installer/compare/v1.0.0...HEAD
