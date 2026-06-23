# Group Loan — Flutter app

A premium, offline savings & loan circle (bachat gat) manager.
Members, monthly collection, loans with correct flat-interest/EMI math, penalties,
and a dashboard. All data is stored privately on the device. No server, no internet
needed to run.

---

## What you have here
- `lib/main.dart` — the whole app
- `pubspec.yaml` — dependencies

This is the **source project**, not an installed app. It must be *built* once into
an Android App Bundle (`.aab`) before it can go on the Play Store.

---

## Step 1 — Set up the tools (one time)
1. Install **Flutter**: https://docs.flutter.dev/get-started/install
2. Install **Android Studio** (gives you the Android SDK).
3. In a terminal, run `flutter doctor` and fix anything it flags.

If this feels like a lot, this is the point where most people hand the folder to a
Flutter developer — the project is ready for them.

## Step 2 — Build the project
```bash
# create a fresh Flutter project shell (makes the android/ ios/ folders)
flutter create group_loan_app
cd group_loan_app

# replace the two generated files with the ones from this folder:
#   - copy lib/main.dart   over  group_loan_app/lib/main.dart
#   - copy pubspec.yaml    over  group_loan_app/pubspec.yaml

flutter pub get
flutter run            # test it on a phone/emulator
```

## Step 3 — Make a release build
```bash
flutter build appbundle      # produces build/app/outputs/bundle/release/app-release.aab
# (or) flutter build apk      # produces an .apk you can install directly to test
```

The Play Store needs the **.aab**.

---

## Step 4 — Publish to the Play Store
1. Create a **Google Play Developer account** (one-time ~$25): https://play.google.com/console
2. In Play Console: **Create app** → fill the listing (name, short/long description,
   screenshots, an icon, category).
3. Provide a **Privacy policy** URL (required — even a simple page stating you store
   data only on the device and collect nothing).
4. Complete **Content rating** and **Data safety** forms.
5. Upload the `.aab` under a release track.
6. New personal accounts currently must run a **closed test (≈12+ testers, ~14 days)**
   before production — check the current rule in the Console, Google changes it.
7. Submit for review.

---

## Notes
- **Fonts:** uses Google Fonts (Fraunces + Plus Jakarta Sans), fetched on first run and
  cached. For guaranteed offline typography, download the .ttf files, put them under
  `assets/fonts/`, declare them in `pubspec.yaml`, and swap the `GoogleFonts.*` calls
  for `TextStyle(fontFamily: ...)`.
- **App name / icon:** change the display name in `android/app/src/main/AndroidManifest.xml`
  (`android:label`) and set an icon with the `flutter_launcher_icons` package.
- **Package id:** set a unique `applicationId` in `android/app/build.gradle`
  (e.g. `com.yourname.grouploan`) before publishing.
- **Interest math:** flat/simple — `amount × rate × months ÷ 1200` (annual rate),
  matching the design (₹20,000 at 12% for 10 months → ₹2,000 interest, ₹2,200 EMI).
