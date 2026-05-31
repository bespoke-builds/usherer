import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderWebApiKey1234567890',
    appId: '1:228736580185:web:588d59fb881e6074c68f48',
    messagingSenderId: '228736580185',
    projectId: 'usherer-62ee6',
    authDomain: 'usherer-62ee6.firebaseapp.com',
    storageBucket: 'usherer-62ee6.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDOsVzBj9zkEfbWqNvDsvCAISX9EM7Br3Q',
    appId: '1:228736580185:ios:0556e83bd9d708d3c68f48',
    messagingSenderId: '228736580185',
    projectId: 'usherer-62ee6',
    storageBucket: 'usherer-62ee6.firebasestorage.app',
    iosBundleId: 'com.usherer.usherer',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAu2mglAozpbdJsJ4hIT5LzaGk0oeMUjhs',
    appId: '1:228736580185:android:588d59fb881e6074c68f48',
    messagingSenderId: '228736580185',
    projectId: 'usherer-62ee6',
    storageBucket: 'usherer-62ee6.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderWindowsApiKey12345678',
    appId: '1:228736580185:windows:588d59fb881e6074c68f48',
    messagingSenderId: '228736580185',
    projectId: 'usherer-62ee6',
    authDomain: 'usherer-62ee6.firebaseapp.com',
    storageBucket: 'usherer-62ee6.firebasestorage.app',
  );
}
