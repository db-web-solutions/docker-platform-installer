# Contributing

This is a proprietary repository. Contributions require prior authorization
from Dmitrijs Brujevs.

## Scope

Keep this repository limited to the public bootstrap boundary:

- authenticate to GitHub without persisting or exposing the token;
- select an immutable private Docker Platform release;
- download the matching private installer and source archive;
- delegate installation through a clean `sudo` environment.

Do not duplicate the private installation engine, Docker Platform CLI, Compose
runtime, host bootstrap, or application deployment logic here.

## Change requirements

- Keep the bootstrap self-contained and compatible with current Linux Bash.
- Preserve exact `vMAJOR.MINOR.PATCH` release selection.
- Never pass the GitHub token in command arguments, environment variables, or
  the privileged process environment.
- Keep the public bootstrap version in `install.sh` synchronized with
  `VERSION`.
- Update `README.md`, `CHANGELOG.md`, and focused documentation for
  user-visible behavior changes.
- Add acceptance coverage for behavior and failure-path changes.

## Validation

Run before submitting a change:

```bash
bash -n install.sh
./install.sh --version
./install.sh --help
./tests/run.sh
git diff --check
```

The test suite must remain isolated: it must not contact GitHub, require a real
token, invoke the real private installer, or require root access.
