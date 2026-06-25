# Group Loan App

Final build with stable PIN login, Firebase sync, Excel-style PDF reports, and WhatsApp PDF sharing.

## Fixed in this version

- App now opens immediately with a luxury loading/login flow.
- Admin / Member PIN login appears before dashboard access.
- After successful PIN login, Home/Dashboard opens automatically.
- More page includes an Open Dashboard / Home button as backup.
- Admin gets full add/edit/delete access.
- Member gets view-only access.
- Firebase Cloud Sync works with the same Group Code.
- VC report and full data are shared as PDF files on WhatsApp.
- Excel-style yearly table format is used in PDF reports.

## Firebase required

- Firestore Database enabled
- Authentication → Anonymous enabled

Phone OTP is not required in this version.

## GitHub Actions

Upload/replace the files in this ZIP and use Actions to build APK/AAB.
