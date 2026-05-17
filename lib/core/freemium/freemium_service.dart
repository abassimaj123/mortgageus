/// Freemium service — re-exports CalcwiseFreemium from library with app-specific configuration.
/// This file maintains backward compatibility while using the shared library implementation.
import 'package:calcwise_core/calcwise_core.dart';

/// Global freemium singleton — handles premium state, rewarded ad sessions, and calc gating.
/// Initialized in main() before other services.
final freemiumService = CalcwiseFreemium(
  appKey: 'mortgageus',
  rewardedDurationMinutes: MonetizationConfig.rewardedDurationMinutes,
  maxRewardedPerDay: MonetizationConfig.maxRewardedPerDay,
  freeCalculationLimit: MonetizationConfig.freeCalculationLimit,
);
