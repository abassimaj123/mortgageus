enum LoanType { conventional, fha, va, jumbo }

extension LoanTypeLabel on LoanType {
  String get label {
    switch (this) {
      case LoanType.conventional: return 'Conventional';
      case LoanType.fha:          return 'FHA';
      case LoanType.va:           return 'VA';
      case LoanType.jumbo:        return 'Jumbo';
    }
  }
}
