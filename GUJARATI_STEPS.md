# APK કેવી રીતે મેળવવી — સહેલી રીત (GitHub, computer setup વગર)

આ project માં cloud-build file (`.github/workflows/build.yml`) પહેલેથી છે.
GitHub પર upload કરતાં જ APK આપોઆપ બની જશે.

## પગલાં
1. **GitHub.com** પર free account બનાવો.
2. **New repository** બનાવો (નામ ગમે તે, દા.ત. `group-loan-app`).
3. આ folder ની બધી ફાઈલો એ repository માં upload કરો
   (વેબસાઈટ પર "Add file → Upload files" — `.zip` ખોલીને બધું drag કરો).
   ⚠️ `.github` folder પણ ચોક્કસ upload થાય એ જોજો.
4. ઉપર **Actions** tab પર જાઓ. Build આપોઆપ ચાલુ થઈ જશે
   (ન થાય તો "Build APK" → "Run workflow" દબાવો).
5. થોડી મિનિટ રાહ જુઓ → લીલી ✓ આવે પછી એ run પર tap કરો.
6. નીચે **Artifacts** માં **group-loan-apk** download કરો → zip ખોલો →
   અંદર **app-release.apk** મળશે.
7. એ APK phone માં મોકલો → Settings માં **"Unknown apps install"** ON કરો →
   APK પર tap કરી install કરો. ✅

## નોંધ
- Phone માં install કરવા આ **APK** ચાલે.
- **Play Store** પર મૂકવા `.aab` જોઈએ — workflow માં
  `flutter build apk --release` ની જગ્યાએ `flutter build appbundle` કરો,
  અને artifact path `build/app/outputs/bundle/release/app-release.aab` કરો.
- App નું નામ/icon બદલવા README.md જુઓ.
