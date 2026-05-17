import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;
export 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;

// ── Engine ────────────────────────────────────────────────────────────────────

class InsightEngine {
  InsightEngine._();

  /// Returns up to [maxCount] insights (most actionable first) given the
  /// calculation inputs and results available on the main calculator screen.
  ///
  /// Parameters that are null mean the data is not yet available (e.g. income
  /// was not entered, extra-payment calculator not run, etc.).
  static List<Insight> generate({
    // Core result fields
    required double monthlyPITI, // total monthly payment incl. PITI
    required double monthlyPI, // P&I portion only
    required double totalInterest,
    required double homePrice,
    required double loanAmount,
    required double annualRatePct,
    required int termYears,

    // Optional context
    double? monthlyGrossIncome, // from optional income field
    double? totalInterest15yr, // from comparator if available
    double? extraPaymentAmount, // $/month extra
    int? monthsSaved, // months saved from extra payment
    double? interestSavedExtra, // $ saved from extra payment
    double? dti, // front-end DTI ratio (0–1)
    double? maxAffordablePrice, // conservative affordability result
    bool isARM = false, // true when ARM/adjustable loan

    // i18n
    bool isEs = false,
    int maxCount = 3,
  }) {
    final insights = <Insight>[];

    // ── 1. Savings: 15yr vs 30yr comparison ──────────────────────────────────
    if (termYears == 30 && totalInterest15yr != null && totalInterest15yr > 0) {
      final saved = totalInterest - totalInterest15yr;
      if (saved > 0) {
        insights.add(Insight(
          severity: InsightSeverity.good,
          icon: Icons.savings_rounded,
          title: isEs ? 'Ahorro con 15 Años' : '15-Year Savings',
          body: isEs
              ? 'Elegir 15 años en lugar de 30 te ahorraría ${_fmt(saved)} en intereses.'
              : 'Choosing 15yr over 30yr saves you ${_fmt(saved)} in interest.',
        ));
      }
    }

    // ── 2. Interest warning: total interest > 50% of home price ──────────────
    if (homePrice > 0 && totalInterest > homePrice * 0.5) {
      final pct = (totalInterest / homePrice * 100).round();
      insights.add(Insight(
        severity: InsightSeverity.alert,
        icon: Icons.warning_amber_rounded,
        title: isEs ? 'Alto Costo de Interés' : 'High Interest Cost',
        body: isEs
            ? 'Pagarás ${_fmt(totalInterest)} en intereses — $pct% del precio de la vivienda.'
            : 'You\'ll pay ${_fmt(totalInterest)} in interest — $pct% of the home price.',
      ));
    }

    // ── 3. House-poor alert: payment > 35% of monthly gross income ───────────
    if (monthlyGrossIncome != null && monthlyGrossIncome > 0) {
      final ratio = monthlyPITI / monthlyGrossIncome;
      if (ratio > 0.35) {
        insights.add(Insight(
          severity: InsightSeverity.alert,
          icon: Icons.home_rounded,
          title: isEs ? 'Riesgo de Casa Pobre' : 'House-Poor Risk',
          body: isEs
              ? 'El pago supera el 35% del ingreso (${(ratio * 100).toStringAsFixed(1)}%). Considera una vivienda más económica.'
              : 'Payment exceeds 35% of income (${(ratio * 100).toStringAsFixed(1)}%) — house-poor risk.',
        ));
      }
    }

    // ── 4. Early payoff from extra payments ───────────────────────────────────
    if (extraPaymentAmount != null &&
        extraPaymentAmount > 0 &&
        monthsSaved != null &&
        monthsSaved > 0 &&
        interestSavedExtra != null) {
      final yearsSaved = monthsSaved ~/ 12;
      final remMonths = monthsSaved % 12;
      final timeLabel = yearsSaved > 0
          ? (isEs
              ? '$yearsSaved años${remMonths > 0 ? " $remMonths meses" : ""}'
              : '$yearsSaved yr${yearsSaved > 1 ? "s" : ""}${remMonths > 0 ? " $remMonths mo" : ""}')
          : (isEs ? '$remMonths meses' : '$remMonths mo');

      insights.add(Insight(
        severity: InsightSeverity.good,
        icon: Icons.rocket_launch_rounded,
        title: isEs ? 'Pago Anticipado' : 'Early Payoff',
        body: isEs
            ? '${_fmt(extraPaymentAmount)}/mes extra liquida tu préstamo $timeLabel antes y ahorra ${_fmt(interestSavedExtra)}.'
            : '\$${_fmtRaw(extraPaymentAmount)}/mo extra pays off your loan $timeLabel earlier, saving ${_fmt(interestSavedExtra)}.',
      ));
    }

    // ── 5. Safe DTI zone ──────────────────────────────────────────────────────
    if (dti != null && dti < 0.28) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon: Icons.check_circle_outline,
        title: isEs ? 'DTI Saludable' : 'Healthy DTI',
        body: isEs
            ? 'Tu ratio deuda-ingreso del ${(dti * 100).toStringAsFixed(1)}% está bien dentro de los límites del prestamista.'
            : 'DTI of ${(dti * 100).toStringAsFixed(1)}% — well within lender limits.',
      ));
    }

    // ── 6. Rate risk: cost of each 1% rate rise ────────────────────────────────
    // Calculated from the P&I portion using approximation:
    //   ΔPayment ≈ loanAmount * (Δrate/12) / (1 - (1 + newRate/12)^(-n))
    if (loanAmount > 0 && termYears > 0) {
      final n = termYears * 12;
      final rateInc = (annualRatePct + 1.0) / 100 / 12;
      final rateCurr = annualRatePct / 100 / 12;
      final piCurr = rateCurr > 0
          ? loanAmount * rateCurr / (1 - _pow(1 + rateCurr, -n.toDouble()))
          : loanAmount / n;
      final piNew = rateInc > 0
          ? loanAmount * rateInc / (1 - _pow(1 + rateInc, -n.toDouble()))
          : loanAmount / n;
      final delta = (piNew - piCurr).abs().roundToDouble();
      if (delta >= 20) {
        // only show if meaningful
        insights.add(Insight(
          severity: isARM ? InsightSeverity.alert : InsightSeverity.warning,
          icon: Icons.trending_up_rounded,
          title: isEs ? 'Riesgo de Tasa' : 'Rate Risk',
          body: isEs
              ? 'Cada 1% de aumento en la tasa añade ~${_fmt(delta)}/mes a tu pago.'
              : 'Each 1% rate increase adds ~${_fmt(delta)}/mo to your payment.',
        ));
      }
    }

    // ── 7. Affordability: max safe purchase price ─────────────────────────────
    if (maxAffordablePrice != null && maxAffordablePrice > 0) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon: Icons.account_balance_rounded,
        title: isEs ? 'Precio Máximo Seguro' : 'Max Safe Price',
        body: isEs
            ? 'Según tu ingreso, el precio máximo seguro de vivienda es ${_fmt(maxAffordablePrice)}.'
            : 'Based on your income, max safe purchase price is ${_fmt(maxAffordablePrice)}.',
      ));
    }

    // ── Fallback: always show at least one insight after calculation ──────────
    if (insights.isEmpty && totalInterest > 0) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon: Icons.info_outline,
        title: isEs ? 'Costo Total de Interés' : 'Total Interest Cost',
        body: isEs
            ? 'Pagarás ${_fmt(totalInterest)} en intereses totales sobre la vida del préstamo.'
            : 'You\'ll pay ${_fmt(totalInterest)} in total interest over the life of the loan.',
      ));
    }

    // Deduplicate and cap at maxCount (prioritise alerts > warnings > good)
    insights.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final alerts =
        insights.where((i) => i.severity == InsightSeverity.alert).toList();
    final warnings =
        insights.where((i) => i.severity == InsightSeverity.warning).toList();
    final goods =
        insights.where((i) => i.severity == InsightSeverity.good).toList();

    final ordered = [...alerts, ...warnings, ...goods];
    return ordered.take(maxCount).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static double _pow(double base, double exp) {
    // Simple iterative power for negative integer exponents used here.
    if (exp == 0) return 1;
    double result = 1;
    int n = exp.abs().round();
    for (int i = 0; i < n; i++) {
      result *= base;
    }
    return exp < 0 ? 1 / result : result;
  }

  static String _fmt(double amount) {
    final abs = amount.abs();
    String str;
    if (abs >= 1000000) {
      str = '\$${(abs / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      str = '\$${(abs / 1000).toStringAsFixed(1)}K';
    } else {
      str = '\$${abs.toStringAsFixed(0)}';
    }
    return amount < 0 ? '-$str' : str;
  }

  static String _fmtRaw(double amount) {
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}
