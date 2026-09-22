/// 运行时 API 配置 Provider。
///
/// 提供运行时可配置的 API 基础地址和 API Key，
/// 优先使用用户自定义配置，回退到编译期常量。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'settings_provider.dart';

/// 运行时 API 基础地址。
///
/// 用户在设置中配置的自定义地址优先，未配置时使用编译期 `apiBaseUrl`。
final runtimeApiBaseUrlProvider = Provider<String>((ref) {
  final custom = ref.watch(appSettingsProvider.select((s) => s.customApiBaseUrl));
  if (custom.isNotEmpty) return custom;
  return apiBaseUrl;
});

/// 运行时 API Key。
///
/// 用户在设置中配置的自定义 Key，为空时表示使用默认鉴权。
final runtimeApiKeyProvider = Provider<String>((ref) {
  return ref.watch(appSettingsProvider.select((s) => s.customApiKey));
});
