# Releasing Diana

All seven packages share one version (lockstep) and are published to
pub.dev together by [.github/workflows/publish.yml](.github/workflows/publish.yml)
when a `vX.Y.Z` tag is pushed. Authentication uses pub.dev
[automated publishing](https://dart.dev/tools/pub/automated-publishing)
(GitHub OIDC) — there is no token or secret to manage.

## One-time setup

pub.dev only lets you enable automated publishing on a package that
already exists, so the **first** version of each package is published by
hand.

1. From a clean checkout of `main`, publish each package in dependency
   order (`dart pub publish` asks you to sign in with Google the first
   time):

   ```bash
   for p in diana_annotation diana diana_generator \
            diana_auth diana_data diana_grpc diana_observability; do
     (cd packages/$p && dart pub publish) || break
   done
   ```

   Publishing is permanent — a version can be retracted but never deleted.

2. For each package, open `https://pub.dev/packages/<name>/admin` and under
   **Automated publishing** enable *Publishing from GitHub Actions* with:

   | Field | Value |
   |---|---|
   | Repository | `carmonac/diana-be-framework` |
   | Tag pattern | `v{{version}}` |
   | Require GitHub Actions environment | `pub.dev` (recommended) |

3. Optional: add required reviewers to the `pub.dev` environment
   (repository **Settings → Environments**) to approve each release
   manually before it uploads.

## Cutting a release

1. Bump every version together (see *Lockstep versioning* in
   [CLAUDE.md](CLAUDE.md)): every `pubspec.yaml`, the cross-package
   `^X.Y.Z` constraints, the example constraints, the dependency snippets
   in the package READMEs and docs, and the CHANGELOGs (root + per-package,
   each starting with `## X.Y.Z`).
2. Run `tool/verify.sh` and commit.
3. Tag and push:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

The workflow checks that the tag matches every package version, runs the
analyzer, dry-runs **all** packages before uploading any, then publishes
them in dependency order. If it fails partway, fix the cause and re-run the
job: packages already on pub.dev at that version are skipped.
