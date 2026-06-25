# Gujarati Steps

## Final update શું છે?

આ versionમાં app open/login issue fix છે.

- App તરત open થશે.
- પહેલા Admin / Member PIN Login screen આવશે.
- PIN નાખ્યા પછી direct Home/Dashboard page open થશે.
- જો More page પર રહી જાય તો Open Dashboard / Home button દબાવો.
- Admin full access રાખશે.
- Member view-only રહેશે.
- Firebase same Group Codeથી બધા phoneમાં same data sync કરશે.
- WhatsAppમાં PDF file share થશે, text નહીં.
- PDF Excel જેવી proper table formatમાં બનશે.

## GitHubમાં update કરવાના files

```
lib/main.dart
pubspec.yaml
.github/workflows/build.yml
README.md
GUJARATI_STEPS.md
lib/firebase_options.dart
android/app/google-services.json
```

Minimum fix માટે:

```
lib/main.dart
```

## Firebaseમાં જરૂરી

```
Firestore Database ✅
Authentication → Anonymous ✅
```

Phone OTP હવે જરૂરી નથી.

## App use flow

```
App open
→ Admin Login
→ Group Code: SB2026
→ Admin PIN નાખો
→ Login
→ Home/Dashboard automatic open
```
