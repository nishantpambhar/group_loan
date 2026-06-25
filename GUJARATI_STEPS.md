# Gujarati Steps - Final Master Build

## GitHub update

ZIP extract કરીને આ files replace/upload કરો:

```text
lib/main.dart
pubspec.yaml
.github/workflows/build.yml
README.md
GUJARATI_STEPS.md
lib/firebase_options.dart
android/app/google-services.json
COMPLETE_WORKING_CHECKLIST.md
```

Minimum required:

```text
lib/main.dart
pubspec.yaml
lib/firebase_options.dart
android/app/google-services.json
```

## Firebase

Firebase Consoleમાં આ બે enabled હોવી જોઈએ:

```text
Firestore Database ✅
Authentication → Anonymous ✅
```

Phone OTP enable કરવાની જરૂર નથી.

## App flow

```text
App open → Admin / Member Login screen
Admin Login → Group Code SB2026 + Admin PIN
First Admin login કરનાર phone જ Admin phone તરીકે lock થશે.
Admin full add/edit/delete કરી શકશે.
Member Login → Same Group Code + Member PIN
Member બધા data જોઈ શકશે, પણ edit/delete નહીં કરી શકે.
```

## WhatsApp PDF

More pageમાં:

```text
Share VC table PDF on WhatsApp
Share all data table PDF on WhatsApp
```

WhatsAppમાં proper PDF table file share થશે.
