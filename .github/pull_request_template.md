## Summary

What changes for the user, and why this approach is the simplest one that works.

## Testing

- [ ] `./scripts/ci.sh` passes
- [ ] New behavior has a test or a headless scenario check
- [ ] Checked the change in the app bundle, not only a bare `swift run` binary

## Docs

- [ ] `README.md` updated for user-visible behavior, commands or paths
- [ ] `docs/ARCHITECTURE.md` updated for module, schema or data-flow changes
- [ ] `CHANGELOG.md` updated under `Unreleased`

## Checklist

- [ ] Font files are still opened read-only and never moved or copied
- [ ] No font files, fixtures, build artifacts or secrets are committed
- [ ] No new dependency without a reason in the pull request
- [ ] Changes stay focused on one behavior

## Related issues

Fixes #
