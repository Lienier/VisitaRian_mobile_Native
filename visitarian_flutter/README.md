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

## Vercel deployment

This repo's deployable site is the generated `build/web` output, not the Flutter source tree itself. Vercel will return a 404 if it is pointed at the repo root or `visitarian_flutter/` without deploying the built web folder.

Build and deploy with:

```powershell
./scripts/deploy_web_to_vercel.ps1
```

The script:

- copies `.env` to `assets/config/web.env` so the web app has the same local fallback in production
- builds the Flutter web app with `--dart-define-from-file`
- copies the tracked `vercel.json` into `build/web`
- deploys `build/web` to Vercel production so SPA routes rewrite to `index.html`

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
