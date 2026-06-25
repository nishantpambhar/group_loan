# Group Loan App

Luxury dark green + gold Flutter app for group savings, collections, loans, penalty, VC yearly report, WhatsApp PDF sharing, Firebase cloud sync, and Admin/Member PIN login.

## Final included features

- First screen Admin / Member PIN login
- No OTP, no SMS, no phone-login billing issue
- Same Group Code multi-phone Firebase sync
- Admin full access, Member view-only access
- Admin can set/change Admin PIN and Member PIN from More → Login PIN Settings
- Month navigation fix
- Member management
- Monthly collection paid/pending
- Member-wise monthly penalty
- Loan issue, EMI, interest, paid history
- Interest expected / received / due popup
- Excel-style VC Year Report in app
- VC.xlsx style PDF table export/share
- Full group data table PDF export/share
- WhatsApp share as PDF file, not plain text
- Firebase Firestore cloud sync
- Same Group Code on multiple phones shows same data

## PDF format

The PDF reports are table-based and follow the uploaded VC workbook format:

- VC `[YEAR]` title
- NAME column
- JAN to DEC monthly columns
- Penalty
- VC(%)
- VC(DR)
- VC(CR)
- Total
- Interest Due / Paid / Percentile
- SUB TOTAL row
- Additional penalty notes
- Loan summary table similar to the workbook loan sheet

## Firebase setup required

Firebase project used by this build:

- Project ID: `group-loan-app-cc5d2`
- Android package: `com.example.group_loan`

Enable these in Firebase Console:

1. Firestore Database
2. Authentication → Anonymous

Phone Authentication is not required for this PIN-login version.

## App login flow

Open app after install:

1. Select `Admin Login` or `Member Login`
2. Enter Group Code, e.g. `SB2026`
3. Tap `Use this Group Code` or directly enter PIN
4. First time Admin Login creates the Admin PIN for that group
5. Admin can open More → Login PIN Settings and set Member PIN
6. Member can login with same Group Code + Member PIN

## Role behavior

- Admin: can add, edit, delete, save collection, issue loans, move loans to paid history, reset/clear data, and set login PINs.
- Member: can view synced group data and share PDF reports, but cannot edit/delete data.
- Logged out: app shows login screen first and dashboard does not open.

## WhatsApp PDF sharing

Open app → More:

- `Share VC table PDF on WhatsApp`
- `Share all data table PDF on WhatsApp`

The app generates a PDF file first, then Android share sheet opens. Select WhatsApp to share the PDF.

## GitHub Actions build

This repo can build APK + AAB using GitHub Actions.

Artifact name:

`group-loan-android-release`

Inside artifact:

- `app-release.apk`
- `app-release.aab`
