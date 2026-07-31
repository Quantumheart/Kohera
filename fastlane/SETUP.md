# fastlane match — iOS signing automation

match stores the distribution cert + App Store profiles encrypted in a
private git repo. CI pulls read-only; rotation is one local command.
Replaces the manual p12 + mobileprovision import steps in `release.yml`.

## One-time local setup

1. Create a **private** GitHub repo to hold the encrypted cert store,
   e.g. `Quantumheart/kohera-certificates`. It must be private — it will
   contain an encrypted copy of the distribution cert and its private key.

2. Install fastlane locally (project Gemfile):
   ```sh
   bundle install
   ```

3. Export the secrets match needs in your shell (or put them in a local
   `.env` you do not commit):
   ```sh
   export MATCH_GIT_URL=https://github.com/Quantumheart/kohera-certificates.git
   export MATCH_PASSWORD="<long random passphrase>"
   export APPSTORE_CONNECT_KEY_ID="<from repo secrets>"
   export APPSTORE_CONNECT_ISSUER_ID="<from repo secrets>"
   # path to the decoded .p8 (decode the base64 secret from release.yml)
   echo -n "<APPSTORE_CONNECT_API_KEY base64>" | base64 --decode > /tmp/AuthKey.p8
   export APPSTORE_CONNECT_KEY_FILEPATH=/tmp/AuthKey.p8
   ```

4. Bootstrap the cert store. This imports/regenerates the distribution cert
   and App Store profiles for both bundle IDs and pushes them encrypted:
   ```sh
   bundle exec fastlane provision
   ```
   - If your existing distribution cert is still valid and you want match
     to reuse it rather than create a new one, import it instead:
     ```sh
     bundle exec fastlane match import \
       --type appstore \
       --app_identifier io.github.quantumheart.kohera
     ```
     (repeat for `...KoheraNotificationService`, or list both)

5. Add the two new repo secrets on GitHub:
   - `MATCH_GIT_URL`
   - `MATCH_PASSWORD`
   The four old secrets become unused after the `release.yml` swap and can
   be deleted once green: `IOS_CERTIFICATE_P12`, `IOS_CERTIFICATE_PASSWORD`,
   `IOS_RUNNER_PROVISION_PROFILE`, `IOS_NSE_PROVISION_PROFILE`.

## Profile naming (one-time in-repo edit)

match names profiles `"match AppStore <bundle id>"` by default, but your
`ios/ExportOptions.plist` + `ios/Runner.xcodeproj/project.pbxproj` reference
profiles **by name** (`Kohera App Store` / `Kohera NSE App Store`).

Pick one:

- **Option A — keep your names.** After `fastlane provision`, open the
  Apple portal, rename the two generated profiles to `Kohera App Store`
  and `Kohera NSE App Store`. Re-run `bundle exec fastlane match import`
  so the renamed profiles are captured into the store. No in-repo edit.
- **Option B — adopt match's names.** Update `ios/ExportOptions.plist`
  `provisioningProfiles` dict and the two `PROVISIONING_PROFILE_SPECIFIER`
  lines in `project.pbxproj` to `match AppStore io.github.quantumheart.kohera`
  (and the NSE variant). Then never think about names again.

Option B is the lower-maintenance long-term choice.

## CI usage (already wired into release.yml after the swap)

```sh
bundle exec fastlane sync_signing
```
`sync_signing` is `match ... --readonly` — pulls, never writes.

## Rotation (the only thing you ever do again)

```sh
export MATCH_GIT_URL=... MATCH_PASSWORD=... APPSTORE_CONNECT_*=...
bundle exec fastlane provision
```
match regenerates the cert + both profiles in sync, commits the encrypted
update to the cert repo. CI keeps working — no secret edits, no p12 export.

## Scope

Only `io.github.quantumheart.kohera` (Runner) and `...KoheraNotificationService`
are managed by match. `KoheraShare` uses automatic development signing and is
not part of the App Store export bundle; add it to `Matchfile` later only if
the share extension is ever bundled into the signed release.