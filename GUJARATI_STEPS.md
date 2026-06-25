# Group Loan App - Gujarati Steps

## GitHubમાં update કરવાનું

ZIP extract કર્યા પછી આ files GitHub repoમાં replace/upload કરો:

```text
lib/main.dart
pubspec.yaml
.github/workflows/build.yml
README.md
GUJARATI_STEPS.md
android/app/google-services.json
lib/firebase_options.dart
```

પછી GitHub Actions success થાય એટલે artifact download કરો:

```text
group-loan-android-release
```

ZIP extract કરશો તો અંદર મળશે:

```text
app-release.apk
app-release.aab
```

## Firebase Consoleમાં enable રાખવાનું

```text
1. Firestore Database
2. Authentication → Anonymous
```

આ PIN-login versionમાં Phone OTP જરૂરી નથી. Phone Authentication, SMS region policy, SHA-1/SHA-256 અને billingની જરૂર નથી.

## App Login Flow

App open થશે એટલે પહેલા login screen આવશે.

```text
Admin Login / Member Login select કરો
Group Code: SB2026 નાખો
Admin PIN નાખો
પહેલીવાર Admin Login કરશો ત્યારે એ PIN Admin PIN તરીકે save થશે
Dashboard open થશે
```

પછી Admin appમાં જઈને Member PIN set કરશે:

```text
More → Login PIN Settings → New Member PIN → Save Login PINs
```

પછી બીજા phoneમાં:

```text
Member Login select કરો
Group Code: SB2026 નાખો
Member PIN નાખો
Login as Member
```

## Role System

```text
Admin: add/edit/delete/save બધું કરી શકે
Member: data જોઈ શકે અને PDF share કરી શકે, edit/delete નહિ કરી શકે
```

## WhatsApp PDF Share

Appમાં More tabમાં જાઓ:

```text
Share VC table PDF on WhatsApp
Share all data table PDF on WhatsApp
```

હવે WhatsAppમાં plain text નહીં જાય. Proper PDF file share થશે.

## PDF Format

PDFમાં Excel જેવી table આવશે:

```text
NAME
JAN થી DEC
Penalty
VC(%)
VC(DR)
VC(CR)
Total
Interest Due
Interest Paid
Percentile
SUB TOTAL
Additional Penalty Notes
Loan table
```
