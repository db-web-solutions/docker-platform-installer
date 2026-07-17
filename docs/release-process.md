# Release Process

The public installer and private Docker Platform use independent semantic
versions and release tags.

## Prepare a release

1. Choose the installer version in `MAJOR.MINOR.PATCH` form.
2. Replace the development version in `VERSION` and the embedded `VERSION`
   constant in `install.sh`.
3. Move the applicable `CHANGELOG.md` entries from `Unreleased` into a dated
   version section.
4. Update README installation URLs only when the recommended public bootstrap
   release changes.
5. Run the complete validation contract:

   ```bash
   bash -n install.sh
   ./install.sh --version
   ./install.sh --help
   ./tests/run.sh
   git diff --check
   ```

6. Confirm `install.sh --version` matches the `VERSION` file.
7. Review the full diff and ensure no token, private content, IDE state, or
   local agent instructions are tracked.

## Publish

1. Commit the complete release state.
2. Create an annotated `vMAJOR.MINOR.PATCH` tag on that commit.
3. Push the branch and tag.
4. Create a published, non-draft, non-prerelease GitHub Release.
5. Verify the tagged raw installer URL.
6. Run one real installation against a disposable prepared host or controlled
   test environment.

## After release

Restore the next development version in `VERSION` and `install.sh` only when
new development begins. Add new changes under `Unreleased`.

Do not move the README bootstrap URL to a new version until that exact tag is
published and verified.

## Rollback

The public bootstrap release is selected by its pinned raw GitHub URL. Roll
back bootstrap behavior by using an older verified installer tag.

The private platform release is selected independently through
`DOCKER_PLATFORM_REF`. Installing an older already-installed private release
reactivates it through the private installation engine; the public bootstrap
does not implement rollback itself.
