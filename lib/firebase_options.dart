import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web options are not configured for this app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Firebase options are configured for Android only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB-yRYTN2FrRc27yc9muVXtFskWsC9A0og',
    appId: '1:719360115385:android:d682db55548b0691291168',
    messagingSenderId: '719360115385',
    projectId: 'group-loan-app-cc5d2',
    storageBucket: 'group-loan-app-cc5d2.firebasestorage.app',
  );
}
