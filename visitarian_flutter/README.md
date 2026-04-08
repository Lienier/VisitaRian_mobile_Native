# visitarian_flutter

A new Flutter project.

## Environment setup

Keep local config in `.env`, but do not bundle it as a Flutter asset. For web builds, values should be injected at build time with `--dart-define-from-file`.

1. Copy `.env.example` to `.env`.
2. Fill in the required Firebase, ORS, TomTom, and Google client values.
3. Run `flutter pub get`.
4. Start the app with compile-time defines:

```powershell
flutter run --dart-define-from-file=.env
```

5. Build the web app the same way:

```powershell
flutter build web --dart-define-from-file=.env
```

## Fix deployed 404s and publish latest APK

This project includes `web/vercel.json` for Vercel SPA routing:

- Existing files are served first (`/assets/*`, `/downloads/*.apk`, etc.).
- Missing app routes fall back to `/index.html` (prevents route 404s).
- Missing files inside `/downloads/*` stay a real 404 (so broken APK links are obvious).

Use this release flow:

1. Build Android APK:

```powershell
flutter build apk --release --split-per-abi --dart-define-from-file=.env
```

2. Copy the latest APK to the deployed web download path:

```powershell
./scripts/publish_android_apk.ps1
```

3. Build web (includes `web/downloads/app-arm64-v8a-release.apk`):

```powershell
flutter build web --release --dart-define-from-file=.env
```

4. Deploy `build/web` to Vercel.
5. In the admin panel (`Distribution`), set:
   - `androidApkUrl`: `https://www.visitarian.app/downloads/app-arm64-v8a-release.apk`
   - `latestVersion` and `minSupportedVersion` to match the new app release.

If a value is needed in a browser client, treat it as public and lock it down with provider-side restrictions. Do not place server-only secrets in this app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Manual unit test runner

Run all automated manual-test cases in expanded mode (showing each test output):

```powershell
./scripts/run_manual_unit_tests.ps1
```
