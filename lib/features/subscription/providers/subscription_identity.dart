/// 订阅身份：从 Supabase session 派生出权益对账所需的最小身份信息。
///
/// 把 [SubscriptionController] 与 Supabase 的 `Session` 类型解耦——controller 只依赖
/// 这层轻量值对象，既符合「身份单一来源仍是 supabaseSessionProvider」，
/// 又让 controller 可在测试中通过 override 本 provider 注入身份与切换事件，
/// 无需构造完整 Session。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 对账所需的用户身份快照。
class SubscriptionIdentity {
  /// 是否已经收到认证初始化结果。false 表示仍在等待 Supabase initialSession。
  final bool isResolved;

  /// Supabase user.id；匿名 / 未登录为 null。
  final String? userId;

  /// Supabase access token（用于后端鉴权）；未登录为 null。
  final String? accessToken;

  const SubscriptionIdentity({
    this.userId,
    this.accessToken,
    this.isResolved = true,
  });

  /// Supabase 尚未完成首次认证解析。
  static const SubscriptionIdentity pending = SubscriptionIdentity(
    isResolved: false,
  );

  /// 匿名 / 未登录身份。
  static const SubscriptionIdentity anonymous = SubscriptionIdentity();

  /// 是否已登录。
  bool get isSignedIn => isResolved && userId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionIdentity &&
          isResolved == other.isResolved &&
          userId == other.userId &&
          accessToken == other.accessToken;

  @override
  int get hashCode => Object.hash(isResolved, userId, accessToken);
}

/// 本地固定身份：绕过登录，用固定 userId 维度本地额度存储。
const String kLocalUserId = 'local-user';

/// 当前订阅身份。
///
/// 绕过登录版本：恒为固定本地身份（userId 可用，accessToken 为空）。
final subscriptionIdentityProvider = Provider<SubscriptionIdentity>((ref) {
  return const SubscriptionIdentity(userId: kLocalUserId);
});
