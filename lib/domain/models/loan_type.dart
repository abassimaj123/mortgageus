enum LoanType { conventional, fha, va, jumbo, usda }

extension LoanTypeLabel on LoanType {
  String get label {
    switch (this) {
      case LoanType.conventional: return 'Conventional';
      case LoanType.fha:          return 'FHA';
      case LoanType.va:           return 'VA';
      case LoanType.jumbo:        return 'Jumbo';
      case LoanType.usda:         return 'USDA';
    }
  }
}
