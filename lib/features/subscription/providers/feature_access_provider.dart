/// 付费墙挂接 API：查询某能力是否解锁。
///
/// 绕过会员限制版本：所有功能一律返回 true，无需登录或订阅。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/premium_feature.dart';

part 'feature_access_provider.g.dart';

/// 某 [feature] 当前是否对用户可用。
@riverpod
bool featureAccess(Ref ref, PremiumFeature feature) {
  // 绕过会员限制：所有功能一律解锁
  return true;
}
