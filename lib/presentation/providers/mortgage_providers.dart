import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mortgage_us/domain/models/loan_type.dart';
import 'package:mortgage_us/domain/models/mortgage_input.dart';
import 'package:mortgage_us/domain/models/mortgage_result.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';
import 'package:mortgage_us/core/constants/mortgage_constants.dart';

// ── Input state ───────────────────────────────────────────────────────────────

class MortgageInputState {
  final double homePrice;
  final double downPaymentPct;
  final bool   downPaymentAsDollar;
  final double annualRatePct;
  final int    termYears;
  final LoanType loanType;
  final double propertyTaxRatePct;
  final double homeInsuranceAnnual;
  final double hoaMonthly;

  const MortgageInputState({
    this.homePrice           = 400000,
    this.downPaymentPct      = MortgageConstants.defaultDownPaymentPct,
    this.downPaymentAsDollar = false,
    this.annualRatePct       = MortgageConstants.defaultInterestRate,
    this.termYears           = MortgageConstants.defaultTermYears,
    this.loanType            = LoanType.conventional,
    this.propertyTaxRatePct  = MortgageConstants.defaultPropertyTaxRate,
    this.homeInsuranceAnnual = MortgageConstants.defaultHomeInsurance,
    this.hoaMonthly          = 0,
  });

  double get downPaymentDollar => homePrice * downPaymentPct / 100.0;

  MortgageInputState copyWith({
    double?   homePrice,
    double?   downPaymentPct,
    bool?     downPaymentAsDollar,
    double?   annualRatePct,
    int?      termYears,
    LoanType? loanType,
    double?   propertyTaxRatePct,
    double?   homeInsuranceAnnual,
    double?   hoaMonthly,
  }) => MortgageInputState(
    homePrice:           homePrice           ?? this.homePrice,
    downPaymentPct:      downPaymentPct      ?? this.downPaymentPct,
    downPaymentAsDollar: downPaymentAsDollar ?? this.downPaymentAsDollar,
    annualRatePct:       annualRatePct       ?? this.annualRatePct,
    termYears:           termYears           ?? this.termYears,
    loanType:            loanType            ?? this.loanType,
    propertyTaxRatePct:  propertyTaxRatePct  ?? this.propertyTaxRatePct,
    homeInsuranceAnnual: homeInsuranceAnnual ?? this.homeInsuranceAnnual,
    hoaMonthly:          hoaMonthly          ?? this.hoaMonthly,
  );
}

class MortgageInputNotifier extends StateNotifier<MortgageInputState> {
  MortgageInputNotifier() : super(const MortgageInputState());

  void updateHomePrice(double v)       => state = state.copyWith(homePrice: v);
  void updateDownPaymentPct(double v)  => state = state.copyWith(downPaymentPct: v);
  void updateRate(double v)            => state = state.copyWith(annualRatePct: v);
  void updateTerm(int v)               => state = state.copyWith(termYears: v);
  void updateLoanType(LoanType v)      => state = state.copyWith(loanType: v);
  void updatePropertyTaxRate(double v) => state = state.copyWith(propertyTaxRatePct: v);
  void updateHomeInsurance(double v)   => state = state.copyWith(homeInsuranceAnnual: v);
  void updateHoa(double v)             => state = state.copyWith(hoaMonthly: v);
  void toggleDownPaymentMode(bool dollar) => state = state.copyWith(downPaymentAsDollar: dollar);
}

final mortgageInputProvider =
    StateNotifierProvider<MortgageInputNotifier, MortgageInputState>(
  (_) => MortgageInputNotifier(),
);

// ── Derived: MortgageInput ────────────────────────────────────────────────────

final mortgageInputModelProvider = Provider<MortgageInput>((ref) {
  final s = ref.watch(mortgageInputProvider);
  final pmiRate = (s.homePrice > 0 &&
      (s.downPaymentDollar / s.homePrice) < 0.20 &&
      s.loanType != LoanType.va)
      ? MortgageConstants.pmiDefaultAnnualRate * 100
      : 0.0;

  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month + 1);

  return MortgageInput(
    homePrice:            s.homePrice,
    downPayment:          s.downPaymentDollar,
    annualRatePct:        s.annualRatePct,
    termYears:            s.termYears,
    loanType:             s.loanType,
    propertyTaxRatePct:   s.propertyTaxRatePct,
    homeInsuranceAnnual:  s.homeInsuranceAnnual,
    hoaMonthly:           s.hoaMonthly,
    pmiAnnualRatePct:     pmiRate,
    startDate:            startDate,
  );
});

// ── Derived: result ────────────────────────────────────────────────────────────

final mortgageResultProvider = Provider<MortgageResult?>((ref) {
  final input = ref.watch(mortgageInputModelProvider);
  if (input.homePrice <= 0 || input.termYears <= 0 || input.annualRatePct < 0) return null;
  if (input.loanAmount < 0) return null;
  try {
    return MortgageCalculator.calculate(input);
  } catch (_) {
    return null;
  }
});
