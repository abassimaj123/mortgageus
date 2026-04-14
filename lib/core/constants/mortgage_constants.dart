/// US Mortgage Constants — 2026
/// Update conforming limits each January per FHFA announcement.
class MortgageConstants {
  // ── Conforming loan limits 2026 (FHFA official) ──────────────────────────
  static const double conformingLimit1Unit    = 832750.0;   // update 2027
  static const double conformingLimit2Unit    = 1066000.0;
  static const double conformingLimit3Unit    = 1288875.0;
  static const double conformingLimit4Unit    = 1601450.0;
  static const double conformingLimitHighCost = 1249125.0; // LA, NYC, SF, AK, HI

  // ── PMI ──────────────────────────────────────────────────────────────────
  static const double pmiDefaultAnnualRate  = 0.0075; // 0.75% — typical mid-range
  static const double pmiLtvThreshold       = 0.80;   // PMI required above 80% LTV
  static const double pmiAutoCancelLtv      = 0.78;   // HPA auto-cancel at 78%

  // ── FHA ──────────────────────────────────────────────────────────────────
  static const double fhaMinDownPayment     = 0.035;  // 3.5%
  static const double fhaUpfrontMip         = 0.0175; // 1.75% upfront
  static const double fhaAnnualMip          = 0.0055; // 0.55% annual (most common)

  // ── VA ───────────────────────────────────────────────────────────────────
  static const double vaFundingFeeFirst     = 0.0215; // 2.15% first use

  // ── Defaults ─────────────────────────────────────────────────────────────
  static const double defaultInterestRate    = 6.5;    // % — April 2026 market
  static const int    defaultTermYears       = 30;
  static const double defaultPropertyTaxRate = 1.1;   // % — national average
  static const double defaultHomeInsurance   = 1750.0; // $/year average
  static const double defaultDownPaymentPct  = 20.0;   // %
  static const double defaultRefiClosingCosts = 4000.0;

  // ── Term presets ─────────────────────────────────────────────────────────
  static const List<int> termPresets = [10, 15, 20, 30];

  // ── Validation limits ────────────────────────────────────────────────────
  static const double maxHomePriceAllowed   = 50000000.0;
  static const double maxRateAllowed        = 30.0; // %
  static const int    maxTermYearsAllowed   = 50;
}
