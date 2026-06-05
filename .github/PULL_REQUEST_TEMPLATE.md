<!--
  Title: use a Conventional Commits subject, e.g.
    feat(#123): short description
  Allowed types: feat, fix, perf, refactor, style, docs, test, chore, ci, build, revert
-->

## Summary

<!-- What does this PR do and why? One or two sentences. -->

## Changes

<!-- The notable changes, as bullets. Reference files/areas where useful. -->

-

## Testing

<!-- How was this verified? Name the suites/files run. -->

- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes (run `dart run build_runner build --delete-conflicting-outputs` first if mocks changed)

## Screenshots / recordings

<!-- For UI changes, before/after. Delete this section if not applicable. -->

## Linked issues

<!-- Use "Closes #N" for the issue this completes, and "Refs #N" for the epic. -->

Closes #

## Checklist

- [ ] Follows the conventions in `CLAUDE.md` (logging prefix, no stray comments, commit prefixes)
- [ ] Targets `master` (not another feature branch, unless this is an explicitly requested stacked PR)
- [ ] Updated/added tests for the change
