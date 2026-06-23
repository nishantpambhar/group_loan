# Group Loan App

Flutter app for group savings, monthly collection, member-wise penalties, loan tracking and VC yearly Excel-style report.

## Main features

- Members add/remove
- Monthly collection paid/pending
- Month navigation
- Per-member monthly penalty
- Loan issue and payment tracking
- VC yearly report like Excel sheet:
  - Jan-Dec collection
  - Penalty
  - VC (%)
  - VC (DR)
  - VC (CR)
  - Total
  - Interest due
  - Interest paid
  - Percentile
- Data stored locally with SharedPreferences
- GitHub Actions workflow builds APK and AAB

## Build locally

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

## GitHub Actions

Push to `main` or run workflow manually from Actions. Artifacts:

- `app-release.apk` for testing
- `app-release.aab` for Play Store
