# Group Loan App Gujarati Steps

## Firebase માં જરૂરી setting

APK test કરતા પહેલા Firebase Console માં આ 3 વસ્તુ enable કરો:

1. Firestore Database
2. Authentication → Anonymous
3. Authentication → Phone

Phone OTP release APK માં properly ચાલે એ માટે Firebase Console → Project settings → Android app માં SHA-1 અને SHA-256 add કરવી પડશે.

## App માં Firebase Sync

1. App open કરો
2. More tab ખોલો
3. Firebase Cloud Sync section માં Group Code નાખો
4. Example: SB2026
5. Connect / Switch Group દબાવો
6. Status: Cloud sync active (SB2026) દેખાય તો sync OK

## Phone Login

1. More tab ખોલો
2. Phone Login & Role section માં જાઓ
3. Mobile number country code સાથે નાખો
   Example: +919999999999
4. Send OTP દબાવો
5. OTP નાખીને Verify OTP & Login દબાવો

## Admin / Member system

- Group માં સૌથી પહેલા જે phone login કરશે તે Admin બની જશે.
- Admin બધું add/edit/delete કરી શકશે.
- બીજો phone same Group Code થી login કરશે તો Member view-only રહેશે.
- Member data જોઈ શકશે અને PDF share કરી શકશે, પણ edit/delete નહીં કરી શકે.

## WhatsApp PDF Share

More માં:

- Share VC report PDF on WhatsApp
- Share all data PDF on WhatsApp

Button દબાવ્યા પછી PDF generate થશે અને share sheet ખુલશે. ત્યાં WhatsApp select કરવું.

## GitHub APK build

ZIP extract કરીને GitHub repoમાં files replace કરો. પછી Actions tab માં latest green build open કરો અને `group-loan-android-release` artifact download કરો.
