import 'dart:async';

import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

FusionAuthConfig config({
  bool accepted = true,
  bool deferConsentToNative = false,
  bool appSms = false,
  bool startWithSms = false,
  FusionAuthScene scene = FusionAuthScene.login,
  String? phone,
  String token = 'test-auth-token',
  String terms = 'https://example.com/terms',
  String? alternateLoginLabel,
  String? phoneInputLabel,
  String? emailLoginLabel,
  FusionAuthLoginCard? loginCard,
  bool retainNumberPage = false,
}) =>
    FusionAuthConfig(
      authToken: token,
      schemeCode: 'test-scheme',
      appName: 'Example App',
      termsUrl: Uri.parse(terms),
      privacyUrl: Uri.parse('https://example.com/privacy'),
      privacyAccepted: accepted,
      deferConsentToNative: deferConsentToNative,
      appSms: appSms,
      startWithSms: startWithSms,
      scene: scene,
      phoneNumber: phone,
      alternateLoginLabel: alternateLoginLabel,
      phoneInputLabel: phoneInputLabel,
      emailLoginLabel: emailLoginLabel,
      loginCard: loginCard,
      retainNumberPage: retainNumberPage,
    );

Matcher errorCode(String code) =>
    isA<PlatformException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aliyun_fusion_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'verifyToken': 'opaque-proof'};
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('stage notifications are scoped, ordered and wait for UI handoff',
      () async {
    final authentication = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return authentication.future;
    });
    final stages = <FusionAuthStage>[];
    final frame = Completer<void>();
    final result = AliyunFusionAuth.authenticate(config(appSms: true),
        onStageChanged: (stage) async {
      stages.add(stage);
      if (stage == FusionAuthStage.smsSwitching) await frame.future;
    });
    await Future<void>.delayed(Duration.zero);
    final requestId = calls.single.arguments['stageRequestId'];
    Future<void> notify(String stage, {Object? id}) async {
      final reply = Completer<void>();
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('authStageChanged', {
          'requestId': id ?? requestId,
          'stage': stage,
        })),
        (_) => reply.complete(),
      );
      await reply.future;
    }

    await notify('numberReady', id: 'old-session');
    await notify('unknown');
    expect(stages, isEmpty);
    await notify('numberReady');
    await notify('numberReady');
    expect(stages, [FusionAuthStage.numberReady]);
    var acknowledged = false;
    final switchReply = notify('smsSwitching').then((_) => acknowledged = true);
    await Future<void>.delayed(Duration.zero);
    expect(stages, [FusionAuthStage.numberReady, FusionAuthStage.smsSwitching]);
    expect(acknowledged, isFalse);
    frame.complete();
    await switchReply;
    await notify('numberReady');
    expect(stages.length, 2);
    authentication.complete({'verifyToken': 'proof'});
    await result;
    await notify('numberReady');
    expect(stages.length, 2);
  });

  test('retained iOS page stays exclusive until explicit cancellation',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        return {'verifyToken': 'proof', 'numberPageRetained': true};
      }
      return null;
    });
    final result =
        await AliyunFusionAuth.authenticate(config(retainNumberPage: true));
    expect(result.numberPageRetained, isTrue);
    expect(calls.single.arguments['retainNumberPage'], isTrue);
    await expectLater(
        AliyunFusionAuth.authenticate(config()), throwsA(errorCode('busy')));
    await AliyunFusionAuth.cancel();
    final next = await AliyunFusionAuth.authenticate(config());
    expect(next.numberPageRetained, isFalse);
  });

  test('page snapshot preserves frame and cancellation does not retain pixels',
      () async {
    final pixels = Uint8List.fromList([137, 80, 78, 71]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        return {'verifyToken': 'proof', 'numberPageRetained': true};
      }
      if (call.method == 'snapshotNumberPage') {
        return {
          'png': pixels,
          'x': 30.0,
          'y': 200.0,
          'width': 330.0,
          'height': 400.0
        };
      }
      return null;
    });
    expect(await AliyunFusionAuth.snapshotNumberPage(), isNull);
    await AliyunFusionAuth.authenticate(config(retainNumberPage: true));
    final snapshot = await AliyunFusionAuth.snapshotNumberPage();
    expect(snapshot!.png, pixels);
    expect(snapshot.frame, const Rect.fromLTWH(30, 200, 330, 400));
    await AliyunFusionAuth.cancel();
    expect(await AliyunFusionAuth.snapshotNumberPage(), isNull);
    expect(calls.map((call) => call.method),
        ['authenticate', 'snapshotNumberPage', 'cancel']);
  });

  test('snapshot rejects invalid or late native data', () async {
    final pending = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') {
        return {'verifyToken': 'proof', 'numberPageRetained': true};
      }
      if (call.method == 'snapshotNumberPage') return pending.future;
      return null;
    });
    await AliyunFusionAuth.authenticate(config(retainNumberPage: true));
    final snapshot = expectLater(
        AliyunFusionAuth.snapshotNumberPage(), throwsA(errorCode('cancelled')));
    await AliyunFusionAuth.cancel();
    pending.complete({});
    await snapshot;

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') {
        return {'verifyToken': 'proof', 'numberPageRetained': true};
      }
      return {'png': Uint8List(1), 'x': 0, 'y': 0, 'width': -1, 'height': 400};
    });
    await AliyunFusionAuth.authenticate(config(retainNumberPage: true));
    await expectLater(AliyunFusionAuth.snapshotNumberPage(),
        throwsA(errorCode('invalid_result')));
    await AliyunFusionAuth.cancel();
  });

  test('cancelled proof cannot resurrect a retained page', () async {
    final native = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') return native.future;
      return null;
    });
    final pending =
        AliyunFusionAuth.authenticate(config(retainNumberPage: true));
    await Future<void>.delayed(Duration.zero);
    await AliyunFusionAuth.cancel();
    native.complete({'verifyToken': 'late', 'numberPageRetained': true});
    expect((await pending).numberPageRetained, isFalse);
    await AliyunFusionAuth.authenticate(config());
  });

  test('app SMS retains session and validates consent and session identity',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        throw PlatformException(
            code: 'app_sms_ready', details: {'sessionId': 'sms-session'});
      }
      if (call.method == 'submitSmsCode') return {'verifyToken': 'sms-proof'};
      return null;
    });
    await expectLater(AliyunFusionAuth.authenticate(config(appSms: true)),
        throwsA(errorCode('app_sms_ready')));
    expect(AliyunFusionAuth.smsSessionId, 'sms-session');
    await expectLater(
        AliyunFusionAuth.authenticate(config()), throwsA(errorCode('busy')));
    await expectLater(
        AliyunFusionAuth.sendSmsCode(
            sessionId: 'sms-session',
            phone: '13800138000',
            privacyAccepted: false),
        throwsA(errorCode('privacy_not_accepted')));
    await expectLater(
        AliyunFusionAuth.sendSmsCode(
            sessionId: 'stale', phone: '13800138000', privacyAccepted: true),
        throwsA(errorCode('sms_session_expired')));
    expect(calls.length, 1);
    await AliyunFusionAuth.sendSmsCode(
        sessionId: 'sms-session', phone: '13800138000', privacyAccepted: true);
    final proof = await AliyunFusionAuth.submitSmsCode(
        sessionId: 'sms-session',
        phone: '13800138000',
        code: '0123',
        privacyAccepted: true);
    expect(proof.verifyToken, 'sms-proof');
    expect(AliyunFusionAuth.smsSessionId, 'sms-session');
    await AliyunFusionAuth.cancel();
    expect(AliyunFusionAuth.smsSessionId, isNull);
    expect(calls.map((c) => c.method),
        ['authenticate', 'sendSmsCode', 'submitSmsCode', 'cancel']);
  });

  test('explicit SMS requires app SMS', () async {
    await expectLater(AliyunFusionAuth.authenticate(config(startWithSms: true)),
        throwsA(errorCode('invalid_arguments')));
    expect(calls, isEmpty);
  });

  test('returns a proof and passes app agreements to native SDK', () async {
    final result = await AliyunFusionAuth.authenticate(config());
    expect(result.verifyToken, 'opaque-proof');
    expect(calls.single.method, 'authenticate');
    expect(calls.single.arguments, {
      'authToken': 'test-auth-token',
      'schemeCode': 'test-scheme',
      'sceneId': '100001',
      'appName': 'Example App',
      'termsTitle': '用户协议',
      'termsUrl': 'https://example.com/terms',
      'privacyTitle': '隐私政策',
      'privacyUrl': 'https://example.com/privacy',
      'privacyAccepted': true,
    });
  });

  test('does not initialize without explicit consent', () async {
    await expectLater(AliyunFusionAuth.authenticate(config(accepted: false)),
        throwsA(errorCode('privacy_not_accepted')));
    expect(calls, isEmpty);
  });

  test('explicit deferred consent opens login UI without claiming acceptance',
      () async {
    await AliyunFusionAuth.authenticate(
        config(accepted: false, deferConsentToNative: true));
    expect(calls.single.arguments['privacyAccepted'], false);
    expect(calls.single.arguments['deferConsentToNative'], true);
    await expectLater(
        AliyunFusionAuth.authenticate(config(
            accepted: false,
            deferConsentToNative: true,
            scene: FusionAuthScene.resetPassword,
            phone: '13800138000')),
        throwsA(errorCode('privacy_not_accepted')));
    expect(calls.length, 1);
  });

  test('alternate login closes native flow without yielding a proof', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'alternative_login');
    });
    await expectLater(
      AliyunFusionAuth.authenticate(config(alternateLoginLabel: '密码登录')),
      throwsA(errorCode('alternative_login')),
    );
    expect(calls.single.arguments['alternateLoginLabel'], '密码登录');
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'verifyToken': 'new-proof'});
    expect((await AliyunFusionAuth.authenticate(config())).verifyToken,
        'new-proof');
  });

  test('email entry returns a navigation signal without a proof', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'email_login');
    });
    await expectLater(
        AliyunFusionAuth.authenticate(config(emailLoginLabel: '邮箱验证登录')),
        throwsA(errorCode('email_login')));
    expect(calls.single.arguments['emailLoginLabel'], '邮箱验证登录');
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'verifyToken': 'new-proof'});
    expect((await AliyunFusionAuth.authenticate(config())).verifyToken,
        'new-proof');
  });

  test('rejects missing tokens and non-HTTPS or credential-bearing agreements',
      () async {
    for (final invalid in [
      config(token: ' '),
      config(alternateLoginLabel: ' '),
      config(terms: 'http://example.com/terms'),
      config(terms: 'https://user:password@example.com/terms'),
    ]) {
      await expectLater(AliyunFusionAuth.authenticate(invalid),
          throwsA(errorCode('invalid_arguments')));
    }
    expect(calls, isEmpty);
  });

  FusionAuthLoginCard card({
    Rect frame = const Rect.fromLTWH(24, 150, 342, 440),
    double textScale = 1,
  }) =>
      FusionAuthLoginCard(
        frame: frame,
        backgroundColor: const Color(0xFFF8FAFF),
        primaryColor: const Color(0xFF3B82F6),
        textColor: const Color(0xFF17191D),
        secondaryTextColor: const Color(0xFF626872),
        textScale: textScale,
      );

  test('passes card geometry and ARGB colors without exposing a phone number',
      () async {
    await AliyunFusionAuth.authenticate(
        config(phoneInputLabel: '换号', loginCard: card()));
    expect(calls.single.arguments['phoneInputLabel'], '换号');
    expect(calls.single.arguments['loginCard'], {
      'x': 24.0,
      'y': 150.0,
      'width': 342.0,
      'height': 440.0,
      'backgroundColor': 0xFFF8FAFF,
      'primaryColor': 0xFF3B82F6,
      'textColor': 0xFF17191D,
      'secondaryTextColor': 0xFF626872,
      'textScale': 1.0,
      'title': '本机号码一键登录',
    });
    expect(calls.single.arguments.containsKey('phoneNumber'), false);
  });

  test('rejects invalid cards and login-only entries on password reset',
      () async {
    for (final invalid in [
      config(phoneInputLabel: ' '),
      config(emailLoginLabel: ' '),
      config(
          scene: FusionAuthScene.resetPassword,
          phone: '13800138000',
          emailLoginLabel: '邮箱验证登录'),
      config(loginCard: card(frame: const Rect.fromLTWH(-1, 0, 342, 440))),
      config(loginCard: card(frame: const Rect.fromLTWH(0, 0, 200, 440))),
      config(loginCard: card(frame: const Rect.fromLTWH(0, 0, 342, 300))),
      config(loginCard: card(textScale: double.nan)),
      config(loginCard: card(textScale: 2)),
      config(
          scene: FusionAuthScene.resetPassword,
          phone: '13800138000',
          phoneInputLabel: '换号'),
      config(
          scene: FusionAuthScene.resetPassword,
          phone: '13800138000',
          loginCard: card()),
    ]) {
      await expectLater(AliyunFusionAuth.authenticate(invalid),
          throwsA(errorCode('invalid_arguments')));
    }
    expect(calls, isEmpty);
  });

  test('legacy phone_input errors release the busy guard without a proof',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'phone_input');
    });
    await expectLater(
      AliyunFusionAuth.authenticate(config(phoneInputLabel: '换号')),
      throwsA(errorCode('phone_input')),
    );
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'verifyToken': 'new-proof'});
    expect((await AliyunFusionAuth.authenticate(config())).verifyToken,
        'new-proof');
  });

  test('reset requires a phone and passes the configured reset scene',
      () async {
    await expectLater(
        AliyunFusionAuth.authenticate(
            config(scene: FusionAuthScene.resetPassword)),
        throwsA(errorCode('invalid_arguments')));
    await expectLater(AliyunFusionAuth.authenticate(config(phone: 'invalid')),
        throwsA(errorCode('invalid_arguments')));
    await AliyunFusionAuth.authenticate(config(
      scene: FusionAuthScene.resetPassword,
      phone: '13800138000',
    ));
    expect(calls.single.arguments['sceneId'], '100003');
    expect(calls.single.arguments['phoneNumber'], '13800138000');
  });

  test('unsupported platforms do not invoke native methods', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(AliyunFusionAuth.isSupported, false);
    await expectLater(AliyunFusionAuth.authenticate(config()),
        throwsA(errorCode('unsupported_platform')));
    await AliyunFusionAuth.cancel();
    expect(calls, isEmpty);
  });

  test('platform names match GetFusionAuthToken', () {
    expect(AliyunFusionAuth.platform, 'iOS');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AliyunFusionAuth.platform, 'Android');
  });

  test('rejects empty, missing and non-string proofs', () async {
    for (final response in [
      null,
      <String, dynamic>{},
      {'verifyToken': ''},
      {'verifyToken': 42}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(AliyunFusionAuth.authenticate(config()),
          throwsA(errorCode('invalid_result')));
    }
  });

  test('concurrent requests are rejected, cancellation allows a new attempt',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') return pending.future;
      pending.completeError(PlatformException(code: 'cancelled'));
      return null;
    });
    final active = AliyunFusionAuth.authenticate(config());
    final cancelled = expectLater(active, throwsA(errorCode('cancelled')));
    await expectLater(
        AliyunFusionAuth.authenticate(config()), throwsA(errorCode('busy')));
    await AliyunFusionAuth.cancel();
    await cancelled;
    expect(calls.map((call) => call.method), ['authenticate', 'cancel']);
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'verifyToken': 'new-proof'});
    expect((await AliyunFusionAuth.authenticate(config())).verifyToken,
        'new-proof');
  });

  test('SDK errors preserve their code and release the busy guard', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
          code: 'token_auth_failed', message: 'Provider failure');
    });
    await expectLater(AliyunFusionAuth.authenticate(config()),
        throwsA(errorCode('token_auth_failed')));
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'verifyToken': 'retry-proof'});
    expect((await AliyunFusionAuth.authenticate(config())).verifyToken,
        'retry-proof');
  });

  for (final cancellation in ['succeeds', 'throws', 'hangs']) {
    testWidgets('timeout remains recoverable when cancellation $cancellation',
        (tester) async {
      try {
        final oldProof = Completer<Map<String, Object?>>();
        final pendingCancel = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'authenticate') return oldProof.future;
          if (cancellation == 'throws') {
            throw PlatformException(code: 'sdk_cleanup_failed');
          }
          if (cancellation == 'hangs') await pendingCancel.future;
          return null;
        });

        final timedOut = expectLater(
          AliyunFusionAuth.authenticate(config()),
          throwsA(errorCode('timeout')),
        );
        await tester.pump();
        await tester.pump(const Duration(minutes: 5));
        expect(calls.map((call) => call.method), ['authenticate', 'cancel']);
        if (cancellation == 'hangs') {
          await expectLater(
            AliyunFusionAuth.authenticate(config()),
            throwsA(errorCode('busy')),
          );
          await tester.pump(const Duration(seconds: 3));
        }
        await timedOut;

        final newProof = Completer<Map<String, Object?>>();
        messenger.setMockMethodCallHandler(channel, (_) => newProof.future);
        final retry = AliyunFusionAuth.authenticate(config());
        await tester.pump();
        // A stale result must neither complete the retry nor release its guard.
        if (cancellation == 'throws') {
          oldProof.completeError(PlatformException(code: 'late_native_error'));
        } else {
          oldProof.complete({'verifyToken': 'stale-proof'});
        }
        if (cancellation == 'hangs') {
          pendingCancel
              .completeError(PlatformException(code: 'late_cancel_error'));
        }
        await tester.pump();
        await expectLater(
          AliyunFusionAuth.authenticate(config()),
          throwsA(errorCode('busy')),
        );
        newProof.complete({'verifyToken': 'fresh-proof'});
        await tester.pump();
        expect((await retry).verifyToken, 'fresh-proof');
      } finally {
        // Widget-test invariants run before the outer tearDown callback.
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('string representations do not expose authentication tokens', () {
    expect(config().toString(), isNot(contains('test-auth-token')));
    expect(const FusionAuthResult(verifyToken: 'secret-proof').toString(),
        isNot(contains('secret-proof')));
  });
}
