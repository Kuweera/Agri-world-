# Android signing and in-place updates

## Why updates needed an uninstall
Android installs an APK over an installed app only if both are signed with the **same key**.
`.github/workflows/build-android.yml` used to run `keytool -genkeypair` on **every build**, so every APK
had a different signature and Android refused to update. (Package id `com.arnest.agriworld` never changed.)

## What changed
* The workflow now reads one permanent key from three GitHub secrets (below) and uses it for both
  release and debug exports.
* Version code rises on every build: `run number x 10 + 1` (armeabi-v7a) or `+ 2` (arm64-v8a); version name `0.1.<run number>`.
* The build log ends with the signing certificate fingerprint of each APK. It must be identical in every build.
* Without the secrets the workflow still builds, but with a throw-away key, warns, and names the files `...-TEMPKEY.apk`.

## One-time setup (works from a phone browser)
1. GitHub > the repo > Settings > Secrets and variables > Actions > New repository secret. Add:
   * `ANDROID_KEY_ALIAS` = `agriworld`
   * `ANDROID_KEYSTORE_PASSWORD` = the password from `GITHUB_SECRETS.txt`
   * `ANDROID_KEYSTORE_BASE64` = the single line in `keystore_base64.txt`
2. Back up `agriworld.keystore` and the password somewhere safe, outside the repo. `*.keystore` is in `.gitignore`.
3. Run the workflow. In "APK size and signing report" note the SHA-256 fingerprint. Expected for the key made on 2026-10-29:
   `7B:DD:17:8A:DF:99:66:1F:2E:3E:59:29:37:A6:B0:69:77:64:9A:18:3A:59:CB:E0:C2:99:BC:88:F0:7E:4A:DE`
4. **One last uninstall is unavoidable.** The installed game was signed by a throw-away key that no longer exists
   anywhere, so it cannot be matched. Uninstalling removes `user://save.json` (the save). After that, every later
   build installs over the previous one.

## Acceptance test (not yet done)
Build twice, install the first, make a save and buy a machine, install the second over it, confirm Android accepts it
and the save, money, vehicles and fields are intact.
