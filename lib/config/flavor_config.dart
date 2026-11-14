import 'package:flutter/services.dart';

class FlavorConfig {
  FlavorConfig._();

  static bool get isBeta => appFlavor == 'beta';

  static String get packageName =>
      isBeta ? 'com.orailnoor.privateagent.beta' : 'com.orailnoor.privateagent';

  static String get appName => isBeta ? 'PrivateAgent Beta' : 'PrivateAgent';
}
