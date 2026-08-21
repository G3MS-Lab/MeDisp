# MeDis Flutter App

Flutter implementation of the MeDis offline medication dispenser app. It includes local accounts, dispenser slots, medicine entry and schedules, a daily checklist, calendar history, medicine history, allergy records, patient profile, and configurable reminder times.

## Architecture

- `domain/`: entities and repository contracts; no UI or infrastructure dependencies beyond Flutter value types.
- `data/`: secure local authentication and persistent, user-scoped repository adapters.
- `application/`: stateful use-case coordination and dependency scope.
- `screens/` and `widgets/`: feature UI and reusable presentation components.

## Offline accounts and data

The app does not require Supabase, an API key, or an internet connection. Registration and sign-in happen on the device. Account records and the active session are stored using iOS Keychain or Android secure storage. Passwords are never saved as plain text; each password uses a random salt and a PBKDF2-SHA256 hash.

Medication, slot, intake, allergy, profile, and reminder records persist locally and are separated by the authenticated user's random account ID. Signing out keeps that user's records for the next valid sign-in.

Because there is no server, accounts cannot roam between devices and there is no email-based password recovery. Uninstalling the app or clearing its storage may permanently remove local records. A production deployment containing medical data should additionally define an encrypted backup/export and device-loss policy.

The current dispenser adapter stores slot state locally so the end-to-end workflow is functional offline:

```sh
flutter run
```

Real physical dispenser support still requires the manufacturer's BLE service/characteristic UUIDs or Wi-Fi API contract. Implement those details behind `DispenserRepository`; do not place protocol logic in widgets or controllers.

## Run

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Then verify with `flutter analyze` and `flutter test`.
