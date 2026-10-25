import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fusion_auth_config.dart';
import 'fusion_auth_page_snapshot.dart';
import 'fusion_auth_result.dart';
import 'fusion_auth_scene.dart';
import 'fusion_auth_stage.dart';

/// Starts one native authentication flow at a time across plugin instances.
class AliyunFusionAuth {
  static const MethodChannel _channel = MethodChannel('aliyun_fusion_auth');
  static bool _authenticating = false;
  static bool _numberPageRetained = false;
  static int _generation = 0;
  static String? _smsSessionId;
  static int _stageSequence = 0;
  static String? _stageRequestId;
  static String? get smsSessionId => _smsSessionId;

  /// Whether this platform can load the Android or iOS native plugin.
  ///
  /// This does not test SIM availability, carrier coverage or server setup.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Platform spelling expected by the server-side GetFusionAuthToken API.
  static String get platform {
    if (!isSupported) {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'Fusion authentication requires an Android or iOS app.',
      );
    }
    return defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android';
  }

  /// Initializes the SDK and displays its configured authentication UI.
  ///
  /// Throws [PlatformException] for another login method (`alternative_login`),
  /// cancellation (`cancelled`), missing consent
  /// (`privacy_not_accepted`), concurrent requests (`busy`), invalid configuration
  /// (`invalid_arguments`) or SDK/network failures. Authentication waits at most
  /// five minutes, followed by up to three seconds of cancellation cleanup.
  /// Start a new attempt with a fresh server token after failure or expiry.
  /// [onStageChanged] reports number-page presentation and SMS handoff without
  /// completing authentication. A returned future delays the native SMS handoff
  /// until the caller has prepared its form. These events never grant consent.
  static Future<FusionAuthResult> authenticate(FusionAuthConfig config,
      {FusionAuthStageCallback? onStageChanged}) async {
    final currentPlatform = platform;
    if (!config.privacyAccepted &&
        !(config.deferConsentToNative &&
            config.scene == FusionAuthScene.login)) {
      throw PlatformException(
        code: 'privacy_not_accepted',
        message: 'Obtain user consent before initializing authentication.',
      );
    }
    _validate(config);
    if (_authenticating || _smsSessionId != null || _numberPageRetained) {
      throw PlatformException(
          code: 'busy', message: 'Authentication is in progress.');
    }
    _authenticating = true;
    final generation = _generation;
    final requestId = onStageChanged == null
        ? null
        : '${DateTime.now().microsecondsSinceEpoch}-${++_stageSequence}';
    if (requestId != null) {
      _stageRequestId = requestId;
      FusionAuthStage? lastStage;
      Future<void>? stageUpdate;
      _channel.setMethodCallHandler((call) async {
        final data = call.arguments;
        if (_stageRequestId != requestId ||
            call.method != 'authStageChanged' ||
            data is! Map ||
            data['requestId'] != requestId) {
          return;
        }
        final stage = switch (data['stage']) {
          'numberReady' => FusionAuthStage.numberReady,
          'authorizing' => FusionAuthStage.authorizing,
          'smsSwitching' => FusionAuthStage.smsSwitching,
          _ => null,
        };
        if (stage == null) return;
        if (lastStage == null || stage.index > lastStage!.index) {
          lastStage = stage;
          stageUpdate = Future<void>.sync(() => onStageChanged!(stage));
        }
        // Duplicate notifications still wait for the UI handoff already underway.
        await stageUpdate;
      });
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'authenticate',
        {
          'authToken': config.authToken,
          'schemeCode': config.schemeCode,
          'sceneId': config.scene.id,
          'appName': config.appName,
          'termsTitle': config.termsTitle,
          'termsUrl': config.termsUrl.toString(),
          'privacyTitle': config.privacyTitle,
          'privacyUrl': config.privacyUrl.toString(),
          'privacyAccepted': config.privacyAccepted,
          if (requestId != null) 'stageRequestId': requestId,
          if (config.deferConsentToNative) 'deferConsentToNative': true,
          if (config.appSms) 'appSms': true,
          if (config.startWithSms) 'startWithSms': true,
          if (config.phoneNumber != null) 'phoneNumber': config.phoneNumber,
          if (config.alternateLoginLabel != null)
            'alternateLoginLabel': config.alternateLoginLabel,
          if (config.phoneInputLabel != null)
            'phoneInputLabel': config.phoneInputLabel,
          if (config.emailLoginLabel != null)
            'emailLoginLabel': config.emailLoginLabel,
          if (config.loginCard != null) 'loginCard': config.loginCard!.toMap(),
          if (config.retainNumberPage && currentPlatform == 'iOS')
            'retainNumberPage': true,
        },
      ).timeout(const Duration(minutes: 5));
      final token = result?['verifyToken'];
      if (token is! String || token.trim().isEmpty) {
        throw PlatformException(
          code: 'invalid_result',
          message: 'The $currentPlatform SDK returned no verification token.',
        );
      }
      final retained = generation == _generation &&
          config.retainNumberPage &&
          result?['numberPageRetained'] == true;
      _numberPageRetained = retained;
      return FusionAuthResult(verifyToken: token, numberPageRetained: retained);
    } on PlatformException catch (error) {
      if (error.code == 'app_sms_ready' && error.details is Map) {
        final id = (error.details as Map)['sessionId'];
        if (id is String && id.isNotEmpty) _smsSessionId = id;
      }
      rethrow;
    } on TimeoutException {
      try {
        await cancel().timeout(const Duration(seconds: 3));
      } catch (_) {
        // The native watchdog also ends the session; retain the timeout error.
      }
      throw PlatformException(
          code: 'timeout', message: 'Authentication timed out.');
    } finally {
      if (requestId != null && _stageRequestId == requestId) {
        _stageRequestId = null;
        _channel.setMethodCallHandler(null);
      }
      _authenticating = false;
    }
  }

  /// Capture the retained iOS page without closing it or repeating authentication.
  /// Returns null when no number page is retained, including on Android.
  /// Paint this image in the outgoing route, then await [cancel] before navigating
  /// so the native page cannot remain above the destination route.
  static Future<FusionAuthPageSnapshot?> snapshotNumberPage() async {
    if (!isSupported ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !_numberPageRetained) {
      return null;
    }
    final generation = _generation;
    final data =
        await _channel.invokeMapMethod<String, Object?>('snapshotNumberPage');
    if (generation != _generation || !_numberPageRetained) {
      throw PlatformException(
          code: 'cancelled', message: 'Authentication ended.');
    }
    final png = data?['png'];
    final coordinates = ['x', 'y', 'width', 'height'].map((key) => data?[key]);
    if (png is! Uint8List ||
        png.isEmpty ||
        coordinates.any((value) => value is! num || !value.isFinite)) {
      throw PlatformException(
          code: 'invalid_result', message: 'Missing page snapshot.');
    }
    final values =
        coordinates.cast<num>().map((value) => value.toDouble()).toList();
    final frame = Rect.fromLTWH(values[0], values[1], values[2], values[3]);
    if (frame.width <= 0 || frame.height <= 0) {
      throw PlatformException(
          code: 'invalid_result', message: 'Invalid page frame.');
    }
    return FusionAuthPageSnapshot(png: png, frame: frame);
  }

  /// Cancels the active authentication attempt and closes its native UI.
  ///
  /// The pending [authenticate] completes with a `cancelled` PlatformException,
  /// unless a terminal SDK result has already started cleanup.
  /// Calling this while idle is safe. Does not log out an application session.
  static Future<void> cancel() async {
    if (!isSupported) return;
    _generation++;
    _stageRequestId = null;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('cancel');
    _smsSessionId = null;
    _numberPageRetained = false;
  }

  /// Send through the current fusion SDK session. Completion means SDK send
  /// success, never just that a button/action was invoked.
  static Future<void> sendSmsCode(
      {required String sessionId,
      required String phone,
      required bool privacyAccepted}) async {
    await _smsCommand('sendSmsCode', sessionId, phone, privacyAccepted);
  }

  /// Generate a new opaque proof for each entered code. The session stays alive
  /// so a backend rejection can be corrected without leaving the caller's form.
  static Future<FusionAuthResult> submitSmsCode(
      {required String sessionId,
      required String phone,
      required String code,
      required bool privacyAccepted}) async {
    final response = await _smsCommand(
        'submitSmsCode', sessionId, phone, privacyAccepted,
        code: code);
    final token = response is Map ? response['verifyToken'] : null;
    if (token is! String || token.isEmpty) {
      throw PlatformException(
          code: 'invalid_result', message: 'Missing fusion proof.');
    }
    return FusionAuthResult(verifyToken: token);
  }

  static Future<Object?> _smsCommand(
      String method, String sessionId, String phone, bool accepted,
      {String? code}) async {
    if (!accepted) {
      throw PlatformException(
          code: 'privacy_not_accepted', message: '请先阅读并勾选同意下方协议');
    }
    if (_smsSessionId != sessionId) {
      throw PlatformException(
          code: 'sms_session_expired', message: '短信认证已过期，请重新获取验证码');
    }
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone) ||
        (code != null && !RegExp(r'^\d{4,8}$').hasMatch(code))) {
      throw PlatformException(
          code: 'invalid_arguments', message: '请输入正确的手机号和验证码');
    }
    try {
      return await _channel.invokeMethod<Object?>(method, {
        'sessionId': sessionId,
        'phone': phone,
        'privacyAccepted': accepted,
        if (code != null) 'code': code
      }).timeout(const Duration(seconds: 35));
    } on TimeoutException {
      try {
        await cancel().timeout(const Duration(seconds: 3));
      } catch (_) {}
      throw PlatformException(code: 'timeout', message: '短信认证超时，请重新获取验证码');
    } on PlatformException catch (error) {
      if (error.code == 'sms_session_expired') _smsSessionId = null;
      rethrow;
    }
  }

  static void _validate(FusionAuthConfig config) {
    final validPhone = config.phoneNumber == null ||
        RegExp(r'^1[3-9]\d{9}$').hasMatch(config.phoneNumber!);
    if ([
          config.authToken,
          config.schemeCode,
          config.appName,
          config.termsTitle,
          config.privacyTitle
        ].any((value) => value.trim().isEmpty) ||
        config.termsTitle.trim() == config.privacyTitle.trim() ||
        !_isHttps(config.termsUrl) ||
        !_isHttps(config.privacyUrl) ||
        !validPhone ||
        (config.alternateLoginLabel != null &&
            config.alternateLoginLabel!.trim().isEmpty) ||
        (config.phoneInputLabel != null &&
            config.phoneInputLabel!.trim().isEmpty) ||
        (config.emailLoginLabel != null &&
            config.emailLoginLabel!.trim().isEmpty) ||
        (config.loginCard != null && !config.loginCard!.isValid) ||
        ((config.phoneInputLabel != null ||
                config.emailLoginLabel != null ||
                config.loginCard != null) &&
            config.scene != FusionAuthScene.login) ||
        (config.startWithSms && !config.appSms) ||
        (config.appSms && config.scene == FusionAuthScene.resetPassword) ||
        (config.retainNumberPage && config.scene != FusionAuthScene.login) ||
        (config.deferConsentToNative &&
            config.scene != FusionAuthScene.login) ||
        (config.scene == FusionAuthScene.resetPassword &&
            config.phoneNumber == null)) {
      throw PlatformException(
        code: 'invalid_arguments',
        message:
            'Provide a token, scheme, app name, HTTPS agreements and the required phone number.',
      );
    }
  }

  static bool _isHttps(Uri uri) =>
      uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
}
