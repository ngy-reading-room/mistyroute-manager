/// Google Sign-In wrapper for the Sheets sync: initialise once,
/// authenticate, authorise the Sheets scope, return the access
/// token. Any failure before a token exists is reported as
/// [SheetsSetupNeeded] with the steps — the OAuth client /
/// google-services.json setup is a user step (see
/// [sheetsSetupSteps]).
library;

import 'package:google_sign_in/google_sign_in.dart';

import 'sheets_sync_service.dart';

/// The only scope the sync needs (read/write this user's sheets).
const sheetsScope = 'https://www.googleapis.com/auth/spreadsheets';

class GoogleSignInService {
  GoogleSignInService({this.packageName = 'com.ngy.mistyroutemanager'});

  final String packageName;

  /// SHA-1 of ~/workspace/tools/android-debug.keystore (the keystore
  /// the release APK is signed with — stable across rebuilds).
  static const apkSha1 =
      '2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6';

  bool _initialised = false;

  Future<String> signInAndGetAccessToken() async {
    try {
      if (!_initialised) {
        await GoogleSignIn.instance.initialize();
        _initialised = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final authz = await account.authorizationClient.authorizeScopes([
        sheetsScope,
      ]);
      return authz.accessToken;
    } on SheetsSetupNeeded {
      rethrow;
    } on Exception {
      throw SheetsSetupNeeded(sheetsSetupSteps());
    }
  }
}
