# MeDis Flutter App

Flutter implementation of the MeDis connected medication dispenser app. It includes dispenser connection and slots, medicine entry and schedules, a daily checklist, calendar history, medicine history, allergy records, patient profile, and configurable reminder times.

## Architecture

- `domain/`: entities and repository contracts; no UI or infrastructure dependencies beyond Flutter value types.
- `data/`: replaceable in-memory repository adapters. Add Bluetooth/Wi-Fi and persistence adapters here.
- `application/`: stateful use-case coordination and dependency scope.
- `screens/` and `widgets/`: feature UI and reusable presentation components.

The hardware connection is currently simulated through `InMemoryDispenserRepository`. Implement `DispenserRepository` with the dispenser protocol to connect real hardware without changing application or UI code.

## Run

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

The Flutter SDK is not installed in the environment where this source was generated, so run `flutter analyze` and `flutter test` in a Flutter-enabled environment.
