import 'package:calcwise_core/calcwise_core.dart';

/// US Mortgage Constants — 2026
///
/// Conforming loan limits, FHA limits/MIP, VA funding fee and the PMI LTV
/// threshold are sourced from the CalcwiseTax registry (`mortgage('us_federal')`,
/// verified 2026). They are exposed as getters so call sites stay unchanged and
/// pick up remote/cached dataset upgrades automatically. Each getter falls back
/// to the baked 2026 figure if the jurisdiction is somehow absent.
///
/// Registry rates are DECIMAL (0.0055 = 0.55%).
///
/// Values NOT in the registry (default market rate, conventional PMI premium %)
/// remain hardcoded — see the "Market estimates" section.
class MortgageConstants {
  MortgageConstants._();

  static MortgageData? get _us => CalcwiseTax.registry.mortgage('us_federal');

  // ── Conforming loan limits 2026 — from registry ──────────────────────────
  /// 1-unit baseline conforming limit (FHFA). Registry: `conformingBaseline`.
  static double get conformingLimit1Unit => _us?.conformingBaseline ?? 832750.0;

  /// High-cost-area ceiling (LA, NYC, SF, AK, HI). Registry: `conformingCeiling`.
  static double get conformingLimitHighCost =>
      _us?.conformingCeiling ?? 1249125.0;

  // Multi-unit limits are not in the registry (single-family is the modeled
  // case); kept as published 2026 FHFA figures.
  static const double conformingLimit2Unit = 1066000.0;
  static const double conformingLimit3Unit = 1288875.0;
  static const double conformingLimit4Unit = 1601450.0;

  // ── PMI ──────────────────────────────────────────────────────────────────
  /// PMI required above this LTV (decimal). Registry: `pmiAppliesAboveLtv`.
  static double get pmiLtvThreshold => _us?.pmiAppliesAboveLtv ?? 0.80;

  static const double pmiAutoCancelLtv = 0.78; // HPA auto-cancel at 78%

  // ── FHA — from registry (rates are DECIMAL) ──────────────────────────────
  /// FHA upfront MIP. Registry: `fhaUpfrontMip` (0.0175 = 1.75%).
  static double get fhaUpfrontMip => _us?.fhaUpfrontMip ?? 0.0175;

  /// FHA annual MIP for high-LTV loans (most common).
  /// Registry: `fhaAnnualMipHighLtv` (0.0055 = 0.55%).
  static double get fhaAnnualMip => _us?.fhaAnnualMipHighLtv ?? 0.0055;

  /// FHA annual MIP for low-LTV loans. Registry: `fhaAnnualMipLowLtv`.
  static double get fhaAnnualMipLowLtv => _us?.fhaAnnualMipLowLtv ?? 0.005;

  /// FHA floor loan limit. Registry: `fhaFloor`.
  static double get fhaFloor => _us?.fhaFloor ?? 541287.0;

  /// FHA ceiling loan limit. Registry: `fhaCeiling`.
  static double get fhaCeiling => _us?.fhaCeiling ?? 1249125.0;

  static const double fhaMinDownPayment = 0.035; // 3.5% (statutory minimum)

  // ── VA — from registry (rates are DECIMAL) ───────────────────────────────
  /// VA funding fee, first use, low down payment (<5%).
  /// Registry: `vaFundingFeeFirstUseLowDown` (0.0215 = 2.15%).
  static double get vaFundingFeeFirst =>
      _us?.vaFundingFeeFirstUseLowDown ?? 0.0215;

  /// VA funding fee, subsequent use, low down payment.
  /// Registry: `vaFundingFeeSubsequentLowDown`.
  static double get vaFundingFeeSubsequent =>
      _us?.vaFundingFeeSubsequentLowDown ?? 0.033;

  // ── Market estimates — NOT in registry, hardcoded ────────────────────────
  // Conventional PMI premium % is a market estimate (varies 0.30-1.5%/yr by
  // lender & credit), not a published statutory figure — kept hardcoded.
  static const double pmiDefaultAnnualRate =
      0.0080; // 0.80% — standard mid-range estimate
  // Default pre-fill shown to user before they enter their own rate; not
  // used for calculations and not a market-accuracy claim.
  static const double defaultInterestRate = 6.5; // %

  // ── Defaults ─────────────────────────────────────────────────────────────
  static const int defaultTermYears = 30;
  static const double defaultPropertyTaxRate = 1.1; // % — national average
  static const double defaultHomeInsurance = 1750.0; // $/year average
  static const double defaultDownPaymentPct = 20.0; // %
  static const double defaultRefiClosingCosts = 4000.0;
  /// Purchase closing costs estimate (decimal % of purchase price).
  /// Used for purchase-analysis tools (e.g. investment property purchases),
  /// distinct from `defaultRefiClosingCosts` which is a flat refi estimate.
  static const double defaultPurchaseClosingCostsPct = 0.02; // 2% of price

  // ── Term presets ─────────────────────────────────────────────────────────
  static const List<int> termPresets = [10, 15, 20, 25, 30];

  // ── Validation limits ────────────────────────────────────────────────────
  static const double maxHomePriceAllowed = 50000000.0;
  static const double maxRateAllowed = 30.0; // %
  static const int maxTermYearsAllowed = 50;
}
