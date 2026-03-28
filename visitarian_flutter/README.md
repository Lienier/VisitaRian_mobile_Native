# visitarian_flutter

A new Flutter project.

## Environment setup

Sensitive app config now lives in `.env`, which is ignored by git.

1. Copy `.env.example` to `.env`.
2. Fill in the required Firebase, ORS, and TomTom values.
3. Run `flutter pub get`.

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
