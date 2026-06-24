# Group Loan App - Gujarati Steps

આ ZIP final changes સાથે છે.

## Add થયેલા features

- Month change fix
- Excel જેવી VC yearly report
- Collection penalty fix
- Dashboardમાં penalty amount update
- Interest card click popup
  - Interest expected
  - Interest credit / received
  - Interest due
- Loan delete ના બદલે paid history
- WhatsApp પર full data share
- WhatsApp પર VC report share
- Firebase cloud sync

## Firebase sync કેવી રીતે કામ કરશે

બધા phoneમાં same data જોવા માટે same Group Code નાખવો.

Example:

```text
Group Code: SB2026
```

Phone 1 માં member add કરશો તો Firebaseમાં save થશે અને Phone 2/Phone 3 માં same Group Code હશે તો same data દેખાશે.

Sync થતું data:

```text
Members
Collection paid/pending
Penalty
Loans
Loan payments
Paid loan history
Interest
VC yearly report
Settings
```

## Firebase Consoleમાં જરૂરી setup

Firebase project ID:

```text
group-loan-app-cc5d2
```

આ બે વસ્તુ enable હોવી જોઈએ:

1. Firestore Database
   - Create database
   - Test mode રાખી શકો શરૂઆતમાં
2. Authentication
   - Anonymous sign-in enable કરવું

## GitHub update કેવી રીતે કરવું

ZIP extract કરો અને GitHub repoમાં આ files replace/upload કરો:

```text
lib/main.dart
lib/firebase_options.dart
pubspec.yaml
.github/workflows/build.yml
README.md
GUJARATI_STEPS.md
android/app/google-services.json
```

Minimum required files:

```text
lib/main.dart
lib/firebase_options.dart
pubspec.yaml
```

## APK build

1. GitHubમાં commit કરો.
2. Actions tab ખોલો.
3. Latest Build Android Release run green success થાય ત્યાં સુધી wait કરો.
4. Artifactsમાંથી `group-loan-android-release` download કરો.
5. ZIP extract કરો.
6. `app-release.apk` install કરો.

## Appમાં Firebase connect

App open કરો → More tab → Firebase Cloud Sync

Group Code નાખો:

```text
SB2026
```

પછી **Connect / Switch Group** click કરો.

Status જો આવું દેખાય તો sync OK:

```text
Cloud sync active (SB2026)
```

જો error આવે તો Firebase Consoleમાં Firestore અને Anonymous Authentication enable છે કે નહીં check કરો.


## WhatsApp PDF share

Appમાં હવે WhatsApp share text તરીકે નહીં જાય. PDF file generate થશે.

- More -> Share all data PDF on WhatsApp
- More -> VC Year Report -> Share VC report PDF on WhatsApp

Button દબાવો પછી Android share sheetમાં WhatsApp select કરો.
