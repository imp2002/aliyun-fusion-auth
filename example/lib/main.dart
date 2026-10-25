import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const FusionAuthExampleApp());

class FusionAuthExampleApp extends StatelessWidget {
  const FusionAuthExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '融合认证示例',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2455a4)),
      ),
      home: const AuthenticationPage(),
    );
  }
}

class AuthenticationPage extends StatefulWidget {
  const AuthenticationPage({super.key});

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  final _formKey = GlobalKey<FormState>();
  final _appName = TextEditingController();
  final _schemeCode = TextEditingController();
  final _authToken = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _termsUrl = TextEditingController();
  final _privacyUrl = TextEditingController();

  FusionAuthScene _scene = FusionAuthScene.login;
  bool _consented = false;
  bool _busy = false;
  String _status = '填写自己的方案与临时鉴权 Token 后，在真机上开始认证。';

  @override
  void dispose() {
    _appName.dispose();
    _schemeCode.dispose();
    _authToken.dispose();
    _phoneNumber.dispose();
    _termsUrl.dispose();
    _privacyUrl.dispose();
    super.dispose();
  }

  String? _requiredValue(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;

  String? _httpsUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return '请输入无账号密码的完整 HTTPS 链接';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty && _scene == FusionAuthScene.login) return null;
    return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone) ? null : '请输入中国大陆 11 位手机号';
  }

  Future<void> _authenticate() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    if (!_consented) {
      setState(() => _status = '请先阅读配置的应用协议与隐私政策，并明确同意。');
      return;
    }

    FocusScope.of(context).unfocus();
    final phone = _phoneNumber.text.trim();
    final config = FusionAuthConfig(
      authToken: _authToken.text.trim(),
      schemeCode: _schemeCode.text.trim(),
      appName: _appName.text.trim(),
      termsUrl: Uri.parse(_termsUrl.text.trim()),
      privacyUrl: Uri.parse(_privacyUrl.text.trim()),
      privacyAccepted: _consented,
      scene: _scene,
      phoneNumber: phone.isEmpty ? null : phone,
    );

    // Keep the SDK token in memory for this attempt only. Do not persist it or
    // put it in logs, analytics, navigation URLs, or --dart-define arguments.
    _authToken.clear();
    setState(() {
      _busy = true;
      _status = '正在打开原生认证页面…';
    });

    try {
      // Production code must submit result.verifyToken to its own backend and
      // await verification before creating a session or resetting a password.
      // This interaction-only demo deliberately does not display or retain it.
      await AliyunFusionAuth.authenticate(config);
      if (!mounted) return;
      setState(() => _status = '取得凭证，须交服务端核验。此示例未登录任何业务账号。');
    } on PlatformException catch (error) {
      if (!mounted) return;
      // Do not interpolate the full exception or its details: future SDK
      // responses may carry sensitive data. Display a controlled message.
      setState(() => _status = _errorMessage(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = '未完成认证，请检查平台集成后重新获取 Token 再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(String code) {
    switch (code) {
      case 'cancelled':
        return '已取消认证。再次发起前请重新填写临时 Token。';
      case 'privacy_not_accepted':
        return '请先阅读并同意应用协议和隐私政策。';
      case 'busy':
        return '已有认证流程进行中，请先完成或取消。';
      case 'invalid_arguments':
        return '认证参数无效，请核对配置和所选场景。';
      case 'unsupported_platform':
        return '请在 Android 或 iOS 设备中运行此示例。';
      case 'auth_token_expired':
      case 'token_expired':
      case 'token_auth_failed':
        return '鉴权 Token 已失效或不匹配，请从服务端获取新 Token。';
      case 'auth_timeout':
      case 'timeout':
        return '认证已超时，请检查网络并重新获取 Token。';
      default:
        return '未完成认证，请核对方案、应用标识和网络后重试。';
    }
  }

  Future<void> _cancel() async {
    try {
      await AliyunFusionAuth.cancel();
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = '暂时无法关闭认证，请使用原生页面的返回按钮。');
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool secret = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        validator: validator ?? _requiredValue,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('融合认证示例')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '使用自己的阿里云方案与应用标识。此示例只演示原生认证页面；'
                      '取得凭证后仍须由业务服务端核验。AccessKey 只保存在服务端。',
                    ),
                    const SizedBox(height: 20),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '认证场景',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<FusionAuthScene>(
                          value: _scene,
                          isExpanded: true,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                              value: FusionAuthScene.login,
                              child: Text('登录 / 注册（100001）'),
                            ),
                            DropdownMenuItem(
                              value: FusionAuthScene.resetPassword,
                              child: Text('重置密码（100003）'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _scene = value);
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _field(controller: _appName, label: '应用名称'),
                    _field(controller: _schemeCode, label: '当前平台的 SchemeCode'),
                    _field(
                      controller: _authToken,
                      label: '服务端签发的临时 authToken',
                      hint: '仅在内存中使用；提交后清空',
                      secret: true,
                    ),
                    _field(
                      controller: _phoneNumber,
                      label: _scene == FusionAuthScene.resetPassword
                          ? '待重置密码的手机号（必填）'
                          : '预填手机号（选填）',
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    _field(
                      controller: _termsUrl,
                      label: '应用用户协议 HTTPS 链接',
                      keyboardType: TextInputType.url,
                      validator: _httpsUrl,
                    ),
                    _field(
                      controller: _privacyUrl,
                      label: '应用隐私政策 HTTPS 链接',
                      keyboardType: TextInputType.url,
                      validator: _httpsUrl,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _consented,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _consented = value ?? false),
                      title: const Text('我已阅读并同意上述应用协议与隐私政策'),
                      subtitle: const Text('请先在浏览器阅读自己填写的链接内容。'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy || !_consented ? null : _authenticate,
                      child: Text(_busy ? '认证进行中…' : '开始认证'),
                    ),
                    if (_busy)
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('取消本次认证'),
                      ),
                    const SizedBox(height: 20),
                    Semantics(liveRegion: true, child: Text(_status)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
