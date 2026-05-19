import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

Widget buildGoogleSignInButton() {
  final plugin = GoogleSignInPlatform.instance as GoogleSignInPlugin;
  return SizedBox(
    height: 44,
    child: plugin.renderButton(
      configuration: GSIButtonConfiguration(
        type: GSIButtonType.standard,
        shape: GSIButtonShape.pill,
        theme: GSIButtonTheme.filledBlue,
        size: GSIButtonSize.large,
        text: GSIButtonText.signinWith,
      ),
    ),
  );
}
