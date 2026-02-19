# VisitaRian Flutter Architecture

This codebase now follows a module-first layout:

- `app/`: app bootstrap and top-level routing.
- `core/`: cross-cutting services and theme entrypoints.
- `features/`: module entrypoints (auth, tour, admin XR).
- `screens/`, `admin/xr/`, `services/`, `theme/`: existing implementation files.

## Entry Points

- `main.dart`: startup only.
- `app/bootstrap.dart`: Firebase + app-level init.
- `app/app.dart`: `MaterialApp` configuration.
- `app/app_routes.dart`: centralized no-argument routes.

## Module Barrels

- `features/auth/auth.dart`
- `features/tour/tour.dart`
- `features/admin_xr/admin_xr.dart`
- `core/services/services.dart`
- `core/theme/theme.dart`

Use these barrel files for cross-feature imports to keep dependencies predictable.
