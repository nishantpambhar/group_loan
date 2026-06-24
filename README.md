# Group Loan App

Luxury dark green + gold Flutter app for group collection, loans, interest, penalty and VC yearly reporting.

## Final features included

- Month navigation fix: previous/next month works correctly.
- Collection page member-wise paid/pending tracking.
- Member-wise monthly penalty entry.
- Dashboard penalty calculation includes collection penalty.
- Interest card popup:
  - Interest expected
  - Interest credit / received
  - Interest due
- Loan paid history:
  - Active loan can be moved to paid history instead of deleting data.
  - Loan payment/interest data is not lost.
- Excel-style VC yearly report:
  - JAN to DEC contribution
  - Penalty
  - VC (%)
  - VC (DR)
  - VC (CR)
  - Total
  - Interest due
  - Interest paid
  - Percentile
  - Additional penalty notes
- WhatsApp share:
  - Full group report
  - VC yearly report
- Firebase cloud sync:
  - Same Group Code shows same data on all phones.
  - Members, collections, penalties, loans, paid history, interest and VC report sync to Firestore.
  - Local storage fallback remains available.

## Firebase project

Project ID: `group-loan-app-cc5d2`
Android package in Firebase config: `com.example.group_loan`

The app uses `lib/firebase_options.dart` for Android Firebase configuration and includes `android/app/google-services.json` for reference.

## Required Firebase console setup

Before building/testing Firebase sync, enable these in Firebase Console:

1. Firestore Database
   - Create database
   - Start in test mode for initial testing
2. Authentication
   - Enable Anonymous sign-in

## Cloud data structure

Firestore stores one document per group code:

```text
groups
  └── SB2026
       ├── groupCode
       ├── appData
       ├── createdAt
       ├── updatedAt
       └── updatedBy
```

Use the same Group Code, for example `SB2026`, on every phone to see the same data.

## GitHub Actions build

The workflow builds APK and AAB:

```text
.github/workflows/build.yml
```

After commit:

1. Open GitHub repo.
2. Go to Actions.
3. Open latest successful Build Android Release run.
4. Download artifact: `group-loan-android-release`.
5. Extract ZIP.
6. Install `app-release.apk`.

## Local build commands

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

## Important notes

- If the new APK does not install over the old one, uninstall the old app first and install the new APK.
- If cloud sync shows error, verify Firestore and Anonymous Authentication are enabled.
- Keep the same Group Code on all phones for shared data.


## PDF WhatsApp share

The WhatsApp share buttons now generate PDF files and open the Android share sheet. Select WhatsApp to send the PDF file instead of plain text.

- More -> VC Year Report -> Share VC report PDF on WhatsApp
- More -> Data -> Share all data PDF on WhatsApp
