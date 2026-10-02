# Android release signing

The release build is signed with a release key that only lives on the build machine or in CI. The
key never ships in the APK, so this does not break the "no secrets in the bundle" rule (guide §2, §14): the
APK carries only the public certificate. Never commit the keystore or its passwords, and never pass them
through `--dart-define` (that would put them in the bundle).

## Local builds

1. Create an upload keystore once, outside the repository or under `android/` (both `*.jks` and
   `key.properties` are gitignored):

   ```bash
   keytool -genkey -v -keystore android/upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties`:

   ```properties
   storeFile=upload.jks
   storePassword=<store password>
   keyAlias=upload
   keyPassword=<key password>
   ```

   `storeFile` is relative to `android/` (an absolute path also works).

3. `flutter build apk --release` (or `appbundle`) now signs with that key.

Back the keystore and passwords up somewhere safe: losing them means installed copies can no longer be
updated.

## CI

Instead of `key.properties`, pass the Gradle properties `releaseStoreFile`, `releaseStorePassword`,
`releaseKeyAlias` and `releaseKeyPassword` through Flutter's `-P` (`--android-project-arg`) flag, from CI
secrets, with the keystore decoded to a file at build time:

```bash
flutter build apk --release \
  -PreleaseStoreFile="$KEYSTORE_PATH" -PreleaseStorePassword="$STORE_PASSWORD" \
  -PreleaseKeyAlias="$KEY_ALIAS" -PreleaseKeyPassword="$KEY_PASSWORD"
```

(Verified 2026-10-02 with a throwaway keystore; `ORG_GRADLE_PROJECT_*` environment variables did not reach
Gradle through `flutter build` in the same test, so use `-P`.)

## What each configuration does

The four values are `storeFile`, `storePassword`, `keyAlias` and `keyPassword`, each read from
`key.properties` or else from the matching `-Prelease…` property. A blank value counts as missing.

| Values set | Release build | Debug build, `flutter run`, Android integration tests |
|---|---|---|
| None | Signed with the **debug** key. Gradle prints "the release build is signed with the DEBUG key. Do not distribute it." | Work as usual, with no warning |
| All four | Signed with the release key | Work as usual (debug builds always use the debug key) |
| Some, not all | **Fails** | **Also fail** |

The debug-key fallback is for local smoke tests on an emulator only: Play rejects such an APK, and it cannot
update an install signed with the release key.

A partial configuration is rejected while Gradle *configures* the app module, before any task runs. So it stops
every Android Gradle invocation, debug ones included, with:

```text
Release signing is partly configured; missing: [keyPassword]
```

(the list names whichever values are missing). This is deliberate: a half-written `key.properties` is a mistake
to fix, not something to sign around silently with the debug key. Complete it, or delete it to get the debug
fallback back. Dart-only commands such as `flutter test` and `flutter analyze` don't run Gradle and are not
affected. (Verified 2026-10-02: `flutter build apk --debug` with `keyPassword` left out fails with the message
above.)
