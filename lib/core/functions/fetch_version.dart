import 'dart:convert';
import 'dart:io';

import 'package:app_version_update/data/models/app_version_data.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../values/consts/consts.dart';
import 'convert_version.dart';

/// Fetch version regarding platform.
/// * ```appleId``` unique identifier in Apple Store, if null, we will use your package name.
/// * ```playStoreId``` unique identifier in Play Store, if null, we will use your package name.
/// * ```country``` (iOS only) region of store, if null, we will use 'us'.
Future<AppVersionData> fetchVersion(
    {String? playStoreId, String? appleId, String? country}) async {
  final packageInfo = await PackageInfo.fromPlatform();
  AppVersionData data = AppVersionData();
  if (Platform.isAndroid) {
    data =
        await fetchAndroid(packageInfo: packageInfo, playStoreId: playStoreId);
  } else if (Platform.isIOS) {
    data = await fetchIOS(
      packageInfo: packageInfo,
      appleId: appleId,
      country: country,
    );
  } else {
    throw "Unknown platform";
  }
  data.canUpdate = await convertVersion(
      version: data.localVersion, versionStore: data.storeVersion);
  return data;
}
Future<AppVersionData> fetchAndroid({
  PackageInfo? packageInfo,
  String? playStoreId,
  String? country,
}) async {
  final appId = playStoreId ?? packageInfo?.packageName;

  if (appId == null || appId.isEmpty) {
    throw Exception('Play Store app ID is missing.');
  }

  final uri = Uri.https(
    'play.google.com',
    '/store/apps/details',
    {'id': appId, if (country != null) 'hl': country},
  );

  final response = await http.get(uri, headers: {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120',
  });

  if (response.statusCode != 200) {
    throw Exception('Failed to load Play Store page');
  }

  final versionMatch = RegExp(
    r'Updated Version\s*-\s*([0-9.]+)',
    caseSensitive: false,
  ).firstMatch(response.body);

  if (versionMatch == null) {
    throw Exception('Unable to extract version from Play Store page');
  }

  return AppVersionData(
    storeVersion: versionMatch.group(1),
    storeUrl: uri.toString(),
    localVersion: packageInfo?.version,
    targetPlatform: TargetPlatform.android,
  );
}

Future<AppVersionData> fetchIOS(
    {PackageInfo? packageInfo, String? appleId, String? country}) async {
  assert(appleId != null || packageInfo != null,
      'One between appleId or packageInfo must not be null');
  var parameters = (appleId != null)
      ? {"id": appleId}
      : {'bundleId': packageInfo?.packageName};
  if (country != null) {
    parameters['country'] = country;
  }
  parameters['version'] = '2';
  var uri = Uri.https(appleStoreAuthority, '/lookup', parameters);
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    final jsonResult = json.decode(response.body);
    final List results = jsonResult['results'];
    if (results.isEmpty) {
      throw "Application not found in Apple Store, verify your app id.";
    } else {
      return AppVersionData(
          storeVersion: jsonResult['results'].first['version'],
          storeUrl: jsonResult['results'].first['trackViewUrl'],
          localVersion: packageInfo?.version,
          targetPlatform: TargetPlatform.iOS);
    }
  } else {
    return throw "Application not found in Apple Store, verify your app id.";
  }
}
