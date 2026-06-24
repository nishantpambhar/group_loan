# Group Loan App

Luxury dark green + gold Flutter app for group savings, collections, loans, penalty, VC yearly report, WhatsApp PDF sharing, Firebase cloud sync, and phone login.

## Included features

- Month navigation fix
- Member management
- Monthly collection paid/pending
- Member-wise monthly penalty
- Loan issue, EMI, interest, paid history
- Interest expected / received / due popup
- Excel-style VC Year Report
- Full data PDF share on WhatsApp
- VC report PDF share on WhatsApp
- Firebase Firestore cloud sync
- Same Group Code on multiple phones shows same data
- Phone number OTP login
- Admin / Member role system

## Firebase setup required

Firebase project used by this build:

- Project ID: `group-loan-app-cc5d2`
- Android package: `com.example.group_loan`

Enable these in Firebase Console before testing phone login:

1. Firestore Database
2. Authentication → Anonymous
3. Authentication → Phone

For release APK phone OTP, add SHA-1 and SHA-256 fingerprints in Firebase Console → Project settings → Your apps → Android app.

## App setup

Open the app:

1. More → Firebase Cloud Sync
2. Group Code: `SB2026`
3. Connect / Switch Group
4. More → Phone Login & Role
5. Enter phone number with country code, e.g. `+919999999999`
6. Send OTP → Verify OTP

The first phone that logs in for a group becomes Admin if no Admin phone is already set.

## Role behavior

- Admin: can add, edit, delete, save collection, issue loans, move loans to paid history, reset/clear data.
- Member: can view synced group data and share PDF reports, but cannot edit/delete data.
- Guest: if Admin is already set, guest acts as view-only.

## GitHub Actions build

This repo can build APK + AAB using GitHub Actions.

Artifact name:

`group-loan-android-release`

Inside artifact:

- `app-release.apk`
- `app-release.aab`
