import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/subscription/models/entitlement.dart';
import 'package:echo_loop/features/subscription/models/premium_feature.dart';
import 'package:echo_loop/features/subscription/providers/feature_access_provider.dart';
import 'package:echo_loop/features/subscription/providers/subscription_controller.dart';
import 'package:echo_loop/features/subscription/services/free_allowance_policy.dart';
import 'package:echo_loop/features/subscription/state/entitlement_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定 state 的 controller 替身（仿 FakeAppSettings 模式：extends + override build）。
class _FixedController extends SubscriptionController {
  _FixedController(this._state);
  final EntitlementState _state;
  @override
  EntitlementState build() => _state;
}

class _DenyPolicy implements FreeAllowancePolicy {
  const _DenyPolicy();
  @override
  bool allows(PremiumFeature feature) => false;
}

void main() {
  ProviderContainer makeContainer({
    required EntitlementState state,
    FreeAllowancePolicy policy = const AlwaysAllowPolicy(),
    bool authenticated = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        subscriptionControllerProvider.overrideWith(
          () => _FixedController(state),
        ),
        freeAllowancePolicyProvider.overrideWithValue(policy),
        isAuthenticatedProvider.overrideWithValue(authenticated),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const feature = PremiumFeature.aiTranscription;
  const pro = EntitlementState(
    status: EntitlementStatus.premium,
    entitlement: Entitlement(isPremium: true),
  );

  test('绕过登录/会员：pro + 拒绝策略 → 解锁', () {
    final container = makeContainer(state: pro, policy: const _DenyPolicy());
    expect(container.read(featureAccessProvider(feature)), isTrue);
  });

  test('绕过登录：未登录 + free + 放行策略 → 解锁', () {
    final container = makeContainer(
      state: const EntitlementState.free(),
      authenticated: false,
    );
    expect(container.read(featureAccessProvider(feature)), isTrue);
  });

  test('绕过登录：未登录 + pro → 解锁', () {
    final container = makeContainer(state: pro, authenticated: false);
    expect(container.read(featureAccessProvider(feature)), isTrue);
  });

  test('绕过会员限制：free + 拒绝策略 → 解锁', () {
    final container = makeContainer(
      state: const EntitlementState.free(),
      policy: const _DenyPolicy(),
    );
    expect(container.read(featureAccessProvider(feature)), isTrue);
  });

  test('绕过会员限制：unknown 中间态 → 解锁', () {
    final allow = makeContainer(state: const EntitlementState.unknown());
    expect(allow.read(featureAccessProvider(feature)), isTrue);

    final deny = makeContainer(
      state: const EntitlementState.unknown(),
      policy: const _DenyPolicy(),
    );
    expect(deny.read(featureAccessProvider(feature)), isTrue);
  });
}
