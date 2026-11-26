import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screen_automation_service.dart';

class AppLauncherService {
  List<AppInfo>? _cachedApps;
  final ScreenAutomationService _screenService = ScreenAutomationService();

  static const Map<String, String> _knownPackages = {
    'whatsapp': 'com.whatsapp',
    'whatsapp business': 'com.whatsapp.w4b',
    'youtube': 'com.google.android.youtube',
    'chrome': 'com.android.chrome',
    'settings': 'com.android.settings',
    'camera': 'com.android.camera',
    'gmail': 'com.google.android.gm',
    'maps': 'com.google.android.apps.maps',
    'google maps': 'com.google.android.apps.maps',
    'telegram': 'org.telegram.messenger',
    'play store': 'com.android.vending',
    'clock': 'com.google.android.deskclock',
    'calculator': 'com.google.android.calculator',
  };

  /// Get all installed apps (cached), including system apps!
  Future<List<AppInfo>> getInstalledApps() async {
    _cachedApps ??= await InstalledApps.getInstalledApps(
      excludeSystemApps: false,
      withIcon: false,
    ).timeout(const Duration(seconds: 6), onTimeout: () => <AppInfo>[]);
    return _cachedApps!;
  }

  /// Clear app cache
  void clearCache() {
    _cachedApps = null;
  }

  /// Find apps matching a query
  Future<List<AppInfo>> searchApps(String query) async {
    final apps = await getInstalledApps();
    final lowerQuery = query.toLowerCase();
    return apps.where((app) {
      return app.name.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Open an app by name (fuzzy match + native package fallback)
  Future<String> openApp(String appName) async {
    final trimmed = appName.trim();
    final lower = trimmed.toLowerCase();
    final matches = await searchApps(trimmed);

    String? targetPkg;
    String displayName = trimmed;

    if (matches.isNotEmpty) {
      AppInfo? target;
      for (final app in matches) {
        if (app.name.toLowerCase() == lower) {
          target = app;
          break;
        }
      }
      target ??= matches.first;
      targetPkg = target.packageName;
      displayName = target.name;
    } else if (_knownPackages.containsKey(lower)) {
      targetPkg = _knownPackages[lower];
    }

    if (targetPkg == null) {
      return 'Could not find app "$appName". Try being more specific.';
    }

    try {
      final launched = await InstalledApps.startApp(targetPkg) ?? false;
      if (launched) {
        return 'Opened $displayName';
      }
    } catch (_) {
      // Fall back to native launchPackage below
    }

    final nativeLaunched = await _screenService.launchPackage(targetPkg);
    if (nativeLaunched) {
      return 'Opened $displayName';
    }
    return 'Error opening $displayName ($targetPkg)';
  }

  /// Open an app by exact package name
  Future<String> openPackage(String packageName) async {
    try {
      final launched = await InstalledApps.startApp(packageName) ?? false;
      if (launched) {
        return 'Launched $packageName';
      }
    } catch (_) {}

    final nativeLaunched = await _screenService.launchPackage(packageName);
    return nativeLaunched
        ? 'Launched $packageName'
        : 'Error launching $packageName';
  }

  /// Open a URL
  Future<String> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Opened $url';
      }
      return 'Cannot open $url';
    } catch (e) {
      return 'Error opening URL: $e';
    }
  }
}
