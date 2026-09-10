# Balance Academy Attendance (Mobile)

Cross-platform (Android + iOS) Flutter app for balance-academy.com's in-center attendance system (assistant role) — the mobile counterpart to `balanceacademy-attendance-desktop`, and a direct clone of `attendance_assistant` (the mostafa-solaiman/amirsalama mobile app) repointed at balance-academy's API.

## Features

Same feature set as `attendance_assistant` — login, center/course selection, roster with QR-scan and manual walk-in search, quiz marks, submit. See that project's README for full details; the only functional differences here are:

- **API target**: `https://balance-academy.com/api` (see `lib/config.dart`)
- **QR code prefix**: `MK-` (balance-academy's student dashboard generates `QrCode::generate('MK-' . student_number)`, no zero-padding) — **different** from mostafa-solaiman/amirsalama's `LQ-` prefix with zero-padding. The parsing logic only does `int.tryParse()` on whatever follows the prefix, so the padding difference doesn't matter, only the prefix string does.

**Deliberately excluded** (same reasoning as the mostafa-solaiman app): WhatsApp reminder-sending. That lives on the desktop app (`balanceacademy-attendance-desktop`), which automates a real linked WhatsApp Web session via a local Node.js helper — not practical to replicate on a stock Android/iOS app.

## Running it

```
flutter pub get
flutter run
flutter build apk --release
flutter build ios --release   # needs a Mac with Xcode - not buildable from this machine
```

## Test account

- Email: `qa-test-assistant@example.com`
- Password: `TestAssist123!`

Shared with the desktop app's test account (same one, created directly against balance-academy's `users`/`assistant_profiles` tables). Delete it once real assistant accounts exist for actual staff.

## Verified

Static analysis clean, widget test passes, debug APK builds successfully. Core API integration (login, centers, courses, roster) verified directly against the live production API via a standalone script exercising the exact same `ApiClient` the GUI uses — all real data, not mocked. The GUI itself is a byte-for-byte copy of `attendance_assistant`'s already fully emulator-tested screens/providers/widgets (only `config.dart` and cosmetic branding strings differ), so the same interaction flow (login → centers → courses → roster → mark present → submit) that was proven working step-by-step on an Android emulator for mostafa-solaiman applies here unchanged.
