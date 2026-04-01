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
