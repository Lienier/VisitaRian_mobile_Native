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

## Managed admin onboarding

Production admin and beneficiary onboarding now uses backend-managed one-time invites.

### What changed

- Super admin actions are handled by Firebase Functions in `functions/`.
- Firestore and Storage rules now treat super-admin-only actions separately from normal admin content editing.
- Invite redemption happens after the invited user signs in or creates an account with the invited email.

### Deployment checklist

1. Run `flutter pub get`.
2. Install Functions dependencies:

```powershell
cd functions
npm install
```

3. Deploy rules and functions:

```powershell
firebase deploy --only firestore:rules,storage,functions
```

4. Sign in with the designated bootstrap account `reineilarayat70@gmail.com`.
5. Open the app profile page once and use `Initialize Super Admin`.
6. Use the new `Super Admin` console inside the admin area to create one-time invites.

### Optional server config

If you need to change the bootstrap email later, set the Functions environment variable `SUPER_ADMIN_EMAILS` before deployment.
