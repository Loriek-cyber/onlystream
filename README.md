# OnlyStream

Minimal cross-platform Flutter streaming client for movies, TV shows, and anime, powered by `media_kit` and the **EasyStream API** backend.

## Architecture & Server Connection

OnlyStream connects to an **EasyStream API** (`v1.0.0`) server for metadata, stream resolution (HLS & torrent HTTP Range streaming), and library/watch-progress sync.

### 1. Local Android Companion Server (On-Device)
- Install the **EasyStream Server** companion app (`com.loriek.easystreamserver`) on your Android device.
- It runs the native Rust backend locally on `http://127.0.0.1:5555`.
- OnlyStream checks companion availability and controls it (`ACTION_START` / `ACTION_STOP`) over the `com.loriek.onlystream/companion` platform channel.

### 2. Remote Docker / PC Server
- Run `easystreamapi` on a PC, NAS, or VPS (e.g. via Docker on port `5555`).
- Set the server URL in OnlyStream's **Settings** screen, or bake a default URL at build time:
  ```bash
  flutter build apk --release --dart-define=API_URL="http://192.168.1.100:5555"
  ```

### 3. Building Your Own Compatible Backend
OnlyStream is decoupled from any specific backend implementation. To write your own compatible backend service (in Rust, Go, Python, Node.js, etc.) or an Android companion server, see the full HTTP & Companion specification in [**`docs/BACKEND_API.md`**](docs/BACKEND_API.md).

Summary of required endpoints:
- `GET /health`
- `GET /search`, `GET /discover`, `GET /genres`
- `GET /media/{kind}/{id}`, `GET /media/tv/{id}/season/{season}`
- `GET /stream/resolve/{kind}/{id}`, `GET /stream/hls/{kind}/{id}`, `GET /stream/torrent/{info_hash}`
- `GET/DELETE /torrents`, `GET/DELETE /torrents/{info_hash}`
- `GET /library`, `GET /library/updates`, `PUT/DELETE /library/{kind}/{id}`, `POST /library/{kind}/{id}/progress`, `POST /library/{kind}/{id}/watched`

## Installing via Obtainium (Android)

You can receive release updates directly via [Obtainium](https://github.com/ImranR98/Obtainium):

1. Open Obtainium and go to **Import/Export -> Obtainium Import**.
2. Import [`obtainium.json`](obtainium.json) from this repository (or add `https://github.com/Loriek-cyber/onlystream` manually with **GitHub** source, APK filter `onlystream-arm64-v8a\.apk`, and prereleases disabled).
3. If the repository is private, add a GitHub Personal Access Token (with read access to repository contents/releases) in Obtainium's **Settings -> GitHub PAT**.

Available Android APKs per release:
- `onlystream-arm64-v8a.apk` (recommended for modern 64-bit ARM devices)
- `onlystream-armeabi-v7a.apk` (32-bit ARM)
- `onlystream-x86_64.apk` (x86_64 devices / emulators)
- `onlystream-universal.apk` (all ABIs)

## Local Development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Local `flutter build apk --release` builds automatically fall back to the Android debug keystore when release signing environment variables are unset.

## GitHub Actions CI/CD & Release Secrets Checklist

The workflow in [`.github/workflows/flutter_build.yml`](.github/workflows/flutter_build.yml) runs `flutter analyze` and `flutter test` first, then builds Android, iOS, Linux, and Windows artifacts in parallel. Tagged releases (`v*`) and `workflow_dispatch` runs publish all successful platform artifacts to a GitHub Release even if another platform build fails (as long as the `test` job passes).

Configure the following in **Repository Settings -> Secrets and variables -> Actions**:

### Required Secrets (for signed Android APKs)
- [ ] `ANDROID_KEYSTORE_B64` — Base64-encoded `.jks` keystore (`base64 -w 0 release.jks`)
- [ ] `ANDROID_KEYSTORE_PASS` — Keystore store password
- [ ] `ANDROID_KEY_ALIAS` — Signing key alias
- [ ] `ANDROID_KEY_PASS` — Signing key password

> If `ANDROID_KEYSTORE_B64` is omitted, CI falls back to debug signing so test/CI builds still succeed.

### Optional Variables
- [ ] `API_URL` (Actions **Variable**) — Optional default EasyStream API URL passed via `--dart-define=API_URL=...`

### Cutting a Release
```bash
git tag v1.0.0
git push origin v1.0.0
```
