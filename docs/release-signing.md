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

## Without a release key

If none of the values is set, the release build falls back to the debug key and Gradle prints a warning
("the release build is signed with the DEBUG key. Do not distribute it."). That is only for local smoke tests
on an emulator: Play rejects it, and it cannot update an install signed with the release key. If only some of
the values are set, the build fails and names the missing ones, instead of silently signing with the debug key.
