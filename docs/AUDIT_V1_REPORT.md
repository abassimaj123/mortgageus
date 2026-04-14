# MortgageUS — Audit Pré-Publication v1

**Date d'audit :** 2026-04-14  
**Auditeur :** Claude Sonnet 4.6 (automatisé, lecture seule)  
**Version app :** 1.0.0+1  
**Flutter :** dernière stable  
**Scope :** Android (iOS nécessite Mac/Xcode — hors scope)

---

## Table des matières

1. [Audit Code Qualité](#1-audit-code-qualité)
2. [Audit Tests](#2-audit-tests)
3. [Audit Calculs](#3-audit-calculs)
4. [Audit UI/UX](#4-audit-uiux)
5. [Audit Navigation](#5-audit-navigation)
6. [Audit Dépendances](#6-audit-dépendances)
7. [Audit Firebase / AdMob](#7-audit-firebase--admob)
8. [Audit Monétisation](#8-audit-monétisation)
9. [Audit Assets](#9-audit-assets)
10. [Audit Permissions](#10-audit-permissions)
11. [Audit Build](#11-audit-build)
12. [Audit Sécurité](#12-audit-sécurité)
13. [Audit Documentation](#13-audit-documentation)
14. [Checklist Finale Pré-Publication](#14-checklist-finale-pré-publication)
15. [Recommandations Priorisées](#15-recommandations-priorisées)

---

## 1. Audit Code Qualité

### 1.1 Comptage de lignes

| Fichier | Lignes |
|---|---|
| `lib/core/utils/number_parser.dart` | 7 |
| `lib/domain/models/loan_type.dart` | 12 |
| `lib/domain/models/refinance_result.dart` | 17 |
| `lib/domain/models/extra_payment_result.dart` | 20 |
| `lib/presentation/providers/ad_free_provider.dart` | 23 |
| `lib/core/formatters/currency_input_formatter.dart` | 25 |
| `lib/domain/models/amortization_entry.dart` | 25 |
| `lib/domain/models/mortgage_input.dart` | 34 |
| `lib/core/services/ad_free_service.dart` | 35 |
| `lib/core/ads/ad_config.dart` | 38 |
| `lib/core/constants/mortgage_constants.dart` | 39 |
| `lib/core/services/analytics_service.dart` | 40 |
| `lib/core/services/crashlytics_service.dart` | 42 |
| `lib/core/firebase/firebase_options.dart` | 47 |
| `lib/core/theme/app_theme.dart` | 48 |
| `lib/domain/models/mortgage_result.dart` | 48 |
| `lib/presentation/widgets/banner_ad_widget.dart` | 57 |
| `lib/core/ads/ad_service.dart` | 78 |
| `lib/presentation/providers/mortgage_providers.dart` | 115 |
| `lib/main.dart` | 190 |
| `lib/presentation/screens/refinance/refinance_screen.dart` | 205 |
| `lib/presentation/screens/extra_payments/extra_payments_screen.dart` | 214 |
| `lib/presentation/widgets/reward_ad_sheet.dart` | 234 |
| `lib/presentation/screens/comparator/comparator_screen.dart` | 261 |
| `lib/domain/usecases/mortgage_calculator.dart` | 315 |
| `lib/presentation/screens/calculator/calculator_screen.dart` | 470 |
| `lib/presentation/screens/amortization/amortization_screen.dart` | 525 |
| **TOTAL** | **3 164** |

27 fichiers Dart. Taille codebase saine pour une app de calculatrice.

---

### 1.2 `flutter analyze` — résultat complet

**Exit code : 1** (1 warning bloque le CI)

| Sévérité | Count | Règle |
|---|---|---|
| ⚠️ warning | 1 | `unused_import` |
| ℹ️ info | 43 | `prefer_const_constructors`, `deprecated_member_use`, etc. |
| ❌ error | 0 | — |

**Warning bloquant :**
```
lib/main.dart:5:8 — Unused import 'core/services/crashlytics_service.dart'
```

**Infos par catégorie :**

| Règle | Occurrences | Fichiers |
|---|---|---|
| `prefer_const_constructors` | 22 | `amortization_screen.dart`, `calculator_screen.dart`, `comparator_screen.dart`, `reward_ad_sheet.dart` |
| `deprecated_member_use` (`.withOpacity`) | 9 | `calculator_screen.dart:239`, `comparator_screen.dart:72,147,149,241,244`, `extra_payments_screen.dart:89`, `refinance_screen.dart:121`, `reward_ad_sheet.dart` |
| `prefer_const_literals_to_create_immutables` | 2 | `amortization_screen.dart:171`, `comparator_screen.dart:107` |
| `avoid_relative_lib_imports` | 1 | `scripts/verify_values.dart:1` (hors lib — non critique) |
| `avoid_print` | 6 | `scripts/verify_values.dart` (hors lib — non critique) |
| `library_private_types_in_public_api` | 1 | `test/calculator/amortization_groups_test.dart:33` |
| `unnecessary_import` | 1 | `test/calculator/currency_formatter_test.dart:1` |

---

### 1.3 Formatage — `dart format`

**24 fichiers sur 27 ont un formatage non-standard.** La liste complète :

```
lib/core/ads/ad_config.dart
lib/core/ads/ad_service.dart
lib/core/constants/mortgage_constants.dart
lib/core/formatters/currency_input_formatter.dart
lib/core/services/analytics_service.dart
lib/core/services/crashlytics_service.dart
lib/core/theme/app_theme.dart
lib/domain/models/amortization_entry.dart
lib/domain/models/extra_payment_result.dart
lib/domain/models/loan_type.dart
lib/domain/models/mortgage_input.dart
lib/domain/models/mortgage_result.dart
lib/domain/models/refinance_result.dart
lib/domain/usecases/mortgage_calculator.dart
lib/main.dart
lib/presentation/providers/ad_free_provider.dart
lib/presentation/providers/mortgage_providers.dart
lib/presentation/screens/amortization/amortization_screen.dart
lib/presentation/screens/calculator/calculator_screen.dart
lib/presentation/screens/comparator/comparator_screen.dart
lib/presentation/screens/extra_payments/extra_payments_screen.dart
lib/presentation/screens/refinance/refinance_screen.dart
lib/presentation/widgets/banner_ad_widget.dart
lib/presentation/widgets/reward_ad_sheet.dart
```

> **Note :** Le formatage personnalisé (alignement des `=` en colonne) est intentionnel mais non-standard. Pas bloquant fonctionnellement, mais fait échouer `dart format --check`.

---

### 1.4 TODOs / FIXMEs / HACs / XXX

| Fichier | Ligne | Tag | Contenu |
|---|---|---|---|
| `lib/core/ads/ad_config.dart` | 17 | TODO | `android app ID from AdMob → android/app/src/main/AndroidManifest.xml` |
| `lib/core/ads/ad_config.dart` | 18 | TODO | `iOS app ID from AdMob → ios/Runner/Info.plist` |
| `lib/core/ads/ad_config.dart` | 23 | TODO | `Create 3 ad units in AdMob for com.mortgageus.calculator (Android)` |
| `lib/core/ads/ad_config.dart` | 29 | TODO | `Create 3 ad units in AdMob for com.mortgageus.calculator (iOS)` |
| `lib/core/firebase/firebase_options.dart` | 30 | TODO | `Replace with values from flutterfire configure output` |
| `lib/main.dart` | 23–24 | commentaire | Firebase init commenté (3 lignes) |

**6 TODOs**, tous liés aux IDs AdMob et Firebase. Aucun FIXME / HACK / XXX.

---

### 1.5 `print()` oubliés

```
Résultat : 0 print() dans lib/
```

✅ Aucun debug print en production.

---

### 1.6 Valeurs hardcodées à risque

| Fichier | Ligne | Valeur | Problème |
|---|---|---|---|
| `lib/domain/models/mortgage_input.dart` | ~20 | `832750.0` | Duplique `MortgageConstants.conformingLimit1Unit` — risque désynchronisation |
| `lib/presentation/screens/comparator/comparator_screen.dart` | ~35 | `pmiRate: 0.0` | PMI forcé à zéro dans le comparateur |
| `lib/presentation/screens/comparator/comparator_screen.dart` | — | `15yr vs 30yr` | Scénarios de comparaison hardcodés |

---

### 1.7 Code mort détecté

| Fichier | Élément | Statut |
|---|---|---|
| `lib/core/services/crashlytics_service.dart` | Toute la classe | Importé dans `main.dart` mais jamais utilisé — import supprimé à faire |
| `lib/core/firebase/firebase_options.dart` | Tout le fichier | Entièrement commenté — stub seulement |
| `AdFreeNotifier.refresh()` | Méthode | Définie mais jamais appelée dans l'app |

---

## 2. Audit Tests

### 2.1 Résultats

```
✅ 120 / 120 tests passent
❌ 0 échecs
⏭️ 0 skips
Durée : ~4 secondes
```

### 2.2 Répartition par fichier

| Fichier | Tests | Status |
|---|---|---|
| `test/mortgage_calculator_test.dart` | 46 | ✅ |
| `test/calculator/payment_test.dart` | 8 | ✅ |
| `test/calculator/pmi_test.dart` | 8 | ✅ |
| `test/calculator/amortization_test.dart` | 13 | ✅ |
| `test/calculator/jumbo_test.dart` | 9 | ✅ |
| `test/calculator/extra_payments_test.dart` | 6 | ✅ |
| `test/calculator/refinance_test.dart` | 7 | ✅ |
| `test/calculator/amortization_groups_test.dart` | 14 | ✅ (1 info lint) |
| `test/calculator/currency_formatter_test.dart` | 8 | ✅ (1 info lint) |
| `test/widget_test.dart` | 1 | ✅ |

### 2.3 Fonctions critiques couvertes

| Fonction | Fichier | Tests | Couvert ? |
|---|---|---|---|
| `calcMonthlyPayment` | `mortgage_calculator.dart:17` | 18 tests | ✅ |
| `buildSchedule` | `mortgage_calculator.dart:39` | 15 tests | ✅ |
| `calculate` (PITI complet) | `mortgage_calculator.dart:121` | 8 tests | ✅ |
| `calcPmiMonthly` | `mortgage_calculator.dart:305` | 8 tests | ✅ |
| `calcExtraPayments` | `mortgage_calculator.dart:190` | 11 tests | ✅ |
| `calcRefinance` | `mortgage_calculator.dart:260` | 12 tests | ✅ |
| PMI drop 78% LTV | `mortgage_calculator.dart:81` | 3 tests | ✅ |
| Conforming limits 2026 | `mortgage_constants.dart` | 8 tests | ✅ |
| `CurrencyInputFormatter` | `currency_input_formatter.dart` | 4 tests | ✅ |
| `parseCurrency` | `number_parser.dart` | 4 tests | ✅ |
| Amortization yearly grouping | `amortization_screen.dart` | 14 tests | ✅ |

### 2.4 Edge cases testés

| Edge Case | Testé ? |
|---|---|
| Loan amount = $0 | ✅ `payment_test.dart` |
| Rate = 0% | ✅ `payment_test.dart` |
| Negative rate | ✅ throws ArgumentError |
| Term = 0 | ✅ throws ArgumentError |
| Down payment = 100% (LTV 0%) | ❌ **Non testé** |
| Valeur très grande (overflow) | ❌ **Non testé** |
| Input négatif home price | ❌ **Non testé** |
| HOA = $0 | ✅ implicite dans les tests standards |
| PMI quand VA loan | ✅ `jumbo_test.dart` |
| Extra payment > monthly payment | ❌ **Non testé** |
| Refinance: même taux | ❌ **Non testé** |

### 2.5 Coverage

Coverage détaillé non disponible (flutter test --coverage non lancé — nécessite lcov). Sur la base de l'analyse structurelle :

- **`mortgage_calculator.dart`** : ~95% estimé (tous les chemins critiques testés)
- **`currency_input_formatter.dart`** : ~90% (4 cas de base + edge cases)
- **Screens (UI)** : ~5% (seul widget_test.dart existe, 1 test de smoke)
- **`ad_free_service.dart`** : 0% (aucun test)
- **`ad_service.dart`** : 0% (aucun test)

---

## 3. Audit Calculs

### 3.1 Formule P&I

**Source officielle :** Freddie Mac / Fannie Mae standard  
`Payment = P × r(1+r)^n / ((1+r)^n − 1)`  
où `r` = taux mensuel, `n` = nombre de mois

**Implémentation trouvée :**
```dart
// mortgage_calculator.dart:15-35
/// Formula: P × r(1+r)^n / ((1+r)^n - 1)
static double calcMonthlyPayment({...}) {
  if (r == 0) return loanAmount / n;          // cas taux 0% géré
  final p = pow(1 + r, n).toDouble();
  return loanAmount * r * p / (p - 1);
}
```

**Verdict : ✅ MATCH EXACT.** Gestion du cas `r=0` correcte.

---

### 3.2 PMI — seuil d'annulation automatique

**Source officielle :** Homeowners Protection Act (HPA) 12 U.S.C. § 4902  
- Annulation automatique à **78% LTV** (basé sur le prix d'achat original)  
- Seuil de demande d'annulation à **80% LTV**

**Implémentation :**
```dart
// mortgage_calculator.dart:76-88
// MortgageConstants : pmiThreshold = 0.80, pmiAutoCancelLtv = 0.78
if (ltv <= MortgageConstants.pmiAutoCancelLtv) {   // 78% LTV
  pmiActive = false;
  ...
}
```

**Note :** LTV calculé sur `newBalance / homePrice` (solde courant / prix d'achat). Conforme HPA — l'annulation se base sur le prix d'achat original, pas la valeur courante.

**Verdict : ✅ CONFORME HPA.**

---

### 3.3 Limites conforming 2026 (FHFA)

| Limite | Valeur attendue (FHFA 2026) | Valeur dans le code | Fichier | Verdict |
|---|---|---|---|---|
| 1-unit conforming | $832,750 | `832750.0` | `mortgage_constants.dart` | ✅ |
| High-cost 1-unit | $1,249,125 | `1249125.0` | `mortgage_constants.dart` | ✅ |

⚠️ **Attention :** La valeur `832750.0` est également hardcodée dans `lib/domain/models/mortgage_input.dart` indépendamment de la constante. Risque de désynchronisation lors des mises à jour annuelles FHFA.

---

### 3.4 Apport minimum par type de prêt

| Type | Apport min officiel | Dans le code | Verdict |
|---|---|---|---|
| Conventional | 3% (Fannie/Freddie) | Non validé à la saisie | ⚠️ Pas de validation min |
| FHA | 3.5% (score ≥ 580) | Non validé | ⚠️ Non implémenté |
| VA | 0% | `pmi: false` si VA ✅ | ✅ PMI exempt |
| Jumbo | Typiquement 10-20% | Non validé | ⚠️ Pas de validation min |

> Les calculatrices de référence (NerdWallet, Bankrate) n'imposent pas non plus de minimum — c'est acceptable pour un outil de simulation.

---

### 3.5 PMI mensuel

**Source :** Fannie Mae / MGIC (~0.5%–1.5% annuel selon LTV)

```dart
// mortgage_calculator.dart:305-315
static double calcPmiMonthly({
  required double loanAmount,
  required double pmiAnnualRatePct,
}) => (loanAmount * pmiAnnualRatePct / 100.0) / 12.0;
```

Calcul sur `loanAmount` (montant initial) — pratique standard de l'industrie. Taux par défaut : `0.75%` annuel.

**Verdict : ✅ CORRECT.**

---

### 3.6 Refinance break-even

```dart
// mortgage_calculator.dart:283-291
final breakEvenMonths = (closingCosts / monthlySavings).ceil();
final makesSense = breakEvenMonths <= 84 && monthlySavings > 0;
```

Seuil "makes sense" : 84 mois (7 ans). Standard industrie = 5-7 ans. ✅

---

### 3.7 Tableau récapitulatif formules

| Calcul | Fichier:Ligne | Formule | Source | Verdict |
|---|---|---|---|---|
| P&I mensuel | `mortgage_calculator.dart:33` | `P×r×(1+r)^n / ((1+r)^n−1)` | Freddie Mac | ✅ |
| PMI annulation | `mortgage_calculator.dart:81` | `solde/prixAchat ≤ 0.78` | HPA 12 U.S.C. § 4902 | ✅ |
| PMI mensuel | `mortgage_calculator.dart:310` | `(loan × rate%) / 12` | Fannie Mae | ✅ |
| Conforming limit | `mortgage_constants.dart:6` | `$832,750` | FHFA 2026 | ✅ |
| High-cost limit | `mortgage_constants.dart:8` | `$1,249,125` | FHFA 2026 | ✅ |
| Break-even refi | `mortgage_calculator.dart:283` | `closingCosts / monthlySavings` | Standard industrie | ✅ |
| Intérêt mensuel | `mortgage_calculator.dart:68` | `balance × monthlyRate` | Amortissement standard | ✅ |

---

## 4. Audit UI/UX

### 4.1 État par écran

| Écran | TextField sans formatter | Boutons sans loading | Erreurs gérées | Dark mode | Semantics |
|---|---|---|---|---|---|
| Calculator | ⚠️ Rate, Tax, Insurance sans CurrencyFormatter | ✅ Réactif (pas de bouton) | ✅ null-safe | ✅ | ❌ Aucun |
| Amortization | N/A (lecture seule) | N/A | ✅ | ✅ | ⚠️ Partiel (1 Semantics sur toggle) |
| Comparator | ✅ | ✅ Réactif | ✅ | ✅ | ❌ Aucun |
| Extra Payments | ⚠️ champs numériques sans formatter entier | ⚠️ Pas de loading sur calculate | ✅ | ✅ | ❌ Aucun |
| Refinance | ⚠️ Rate sans formatter | ⚠️ Pas de loading sur calculate | ✅ | ✅ | ❌ Aucun |

### 4.2 TextFields sans InputFormatter

| Fichier | Champ | Formatter manquant |
|---|---|---|
| `calculator_screen.dart` | Interest Rate | Pas de limite décimales |
| `calculator_screen.dart` | Property Tax Rate | Pas de limite décimales |
| `calculator_screen.dart` | Home Insurance | Pas de CurrencyFormatter |
| `calculator_screen.dart` | HOA Fees | Pas de CurrencyFormatter |
| `extra_payments_screen.dart` | Extra Annual, Lump Sum | Currency présent ✅ |
| `refinance_screen.dart` | New Rate | Pas de limite décimales |

### 4.3 Deprecated `.withOpacity()` — 9 occurrences à migrer

| Fichier | Ligne |
|---|---|
| `calculator_screen.dart` | 239 |
| `comparator_screen.dart` | 72, 147, 149, 241, 244 |
| `extra_payments_screen.dart` | 89 |
| `refinance_screen.dart` | 121 |
| `reward_ad_sheet.dart` | 57 |

Correction : remplacer `.withOpacity(x)` par `.withValues(alpha: x)`.

### 4.4 Types `dynamic` dans les widgets

| Fichier | Classe | Paramètre | À typer |
|---|---|---|---|
| `calculator_screen.dart` | `_HeroCard` | `result` | `MortgageResult?` |
| `calculator_screen.dart` | `_BreakdownCard` | `result` | `MortgageResult?` |

### 4.5 Magic numbers UI (non exhaustif)

Tailles hardcodées dans les écrans : `120` (width splash icon), `120` (height splash icon), `80` (SizedBox bottom padding), `400` (animation duration), `1400` (splash delay). Ces valeurs fonctionnent mais pourraient être des constantes nommées.

### 4.6 Haptic feedback

Aucun `HapticFeedback.lightImpact()` sur les chips ou boutons. Pas bloquant pour v1.

### 4.7 Accessibility

❌ Aucun `Semantics` widget sur les écrans Calculator, Comparator, Extra, Refinance.  
⚠️ Amortization a 1 Semantics partiel (toggle vue).  
❌ Aucun `semanticLabel` sur les images.

---

## 5. Audit Navigation

### 5.1 Carte des écrans

```
App
├── SplashWrapper (1400ms auto-dismiss)
└── MainShell (IndexedStack — 5 tabs)
    ├── [0] CalculatorScreen    ← tab Calculator
    ├── [1] AmortizationScreen  ← tab Schedule
    ├── [2] ComparatorScreen    ← tab Compare
    ├── [3] ExtraPaymentsScreen ← tab Extra
    └── [4] RefinanceScreen     ← tab Refi
    
FAB → RewardAdSheet (modal bottom sheet)
```

### 5.2 Observations

| Critère | Statut |
|---|---|
| Tous les écrans accessibles | ✅ (5 tabs + FAB) |
| Écrans orphelins | ✅ Aucun |
| Back button Android (main tabs) | ✅ IndexedStack = comportement correct |
| Back button sur RewardAdSheet | ✅ Modal dismiss standard |
| Écrans dupliqués | ✅ Aucun |
| Deep linking | ❌ Non implémenté (acceptable v1) |

> L'`IndexedStack` maintient l'état de chaque onglet — comportement correct et performant.

---

## 6. Audit Dépendances

### 6.1 Dépendances directes et versions

| Package | Actuel | Disponible | Versions de retard | Critique ? |
|---|---|---|---|---|
| `flutter_riverpod` | 2.6.1 | 3.3.1 | 1 majeure | ⚠️ |
| `riverpod_annotation` | 2.6.1 | 4.0.2 | 2 majeures | ⚠️ |
| `google_mobile_ads` | 5.3.1 | 8.0.0 | **3 majeures** | 🔴 |
| `share_plus` | 9.0.0 | 13.0.0 | **4 majeures** | ⚠️ |
| `fl_chart` | 0.68.0 | 1.2.0 | 1 majeure | 🟡 |
| `intl` | 0.19.0 | 0.20.2 | 1 mineure | 🟡 |
| `printing` | 5.13.1 | 5.14.3 | 1 patch | ✅ |
| `shared_preferences` | 2.2.3 | — | — | ✅ |
| `pdf` | 3.11.1 | — | — | ✅ |
| `uuid` | 4.4.0 | — | — | ✅ |
| `collection` | 1.18.0 | — | — | ✅ |

**Dev deps :**

| Package | Actuel | Disponible | Note |
|---|---|---|---|
| `flutter_lints` | 3.0.2 | 6.0.0 | 3 majeures |
| `build_runner` | 2.4.14 | 2.13.1 | 1 majeure |
| `riverpod_generator` | 2.6.5 | 4.0.3 | 2 majeures |

**⚠️ Packages transitivement DISCONTINUED :**
- `build_resolvers`
- `build_runner_core`

### 6.2 Point critique : `google_mobile_ads` v5 → v8

`google_mobile_ads` 5.3.1 est **3 majeures en retard**. La v8.0.0 inclut des changements d'API potentiellement breaking (nouveaux formats d'annonces, User Messaging Platform intégrée, API de médiation modifiée). À mettre à jour **avant** la publication pour éviter des rejets potentiels du Play Store liés aux SDKs obsolètes.

### 6.3 Dépendances inutilisées

| Package | Déclaré | Utilisé dans le code |
|---|---|---|
| `uuid` | ✅ `pubspec.yaml` | ❓ Aucune occurrence trouvée dans `lib/` |
| `crashlytics_service.dart` | dans `lib/` | ❌ Import non utilisé dans `main.dart` |

---

## 7. Audit Firebase / AdMob

### 7.1 État Firebase

| Élément | État |
|---|---|
| `firebase_core` dans `pubspec.yaml` | ❌ Absent |
| `firebase_analytics` dans `pubspec.yaml` | ❌ Absent |
| `firebase_crashlytics` dans `pubspec.yaml` | ❌ Absent |
| `google-services.json` | ❌ Absent (attendu : `android/app/`) |
| `firebase_options.dart` | ⚠️ Fichier présent mais 100% commenté |
| Init Firebase dans `main.dart` | ⚠️ Commenté (3 lignes) |
| Analytics events instrumentés | ⚠️ Stub uniquement (`AnalyticsService` log vers `debugPrint`) |
| Crashlytics activé | ❌ Non |

**Firebase est entièrement désactivé.** L'app fonctionne sans, mais la privacy policy mentionne Firebase Analytics et Crashlytics comme actifs — **incohérence légale.**

### 7.2 État AdMob

| Élément | État |
|---|---|
| Initialisation dans `main.dart` | ✅ `AdService.instance.initialize()` |
| Android App ID dans `AndroidManifest.xml` | ⚠️ **TEST ID** `ca-app-pub-3940256099942544~3347511713` |
| iOS App ID dans `Info.plist` | ❓ Non vérifié (Windows) |
| Banner Android ID | ⚠️ **TEST ID** |
| Interstitial Android ID | ⚠️ **TEST ID** |
| Rewarded Android ID | ⚠️ **TEST ID** |
| Switch auto debug/release | ❌ Pas de switch kReleaseMode — IDs figés dans `ad_config.dart` |
| GDPR `DELAY_APP_MEASUREMENT_INIT` | ✅ Présent dans `AndroidManifest.xml` |

**⚠️ Tous les 6 IDs ad units sont des TEST IDs Google.** Une release avec ces IDs ne générera aucun revenu et peut entraîner une suspension du compte AdMob si des impressions réelles sont générées avec les IDs de test.

### 7.3 Analytics events actuellement loggés

```dart
// analytics_service.dart (stub — log en debugPrint uniquement)
'app_open'    // main.dart
```

**Aucun autre event instrumenté.** La classe `AnalyticsService` est un stub — tous les appels Firebase sont commentés.

---

## 8. Audit Monétisation

### 8.1 Intégration Banner

| Écran | Banner présent |
|---|---|
| Calculator | ✅ `BannerAdWidget` en bas de l'écran |
| Amortization | ❌ Absent |
| Comparator | ❌ Absent |
| Extra Payments | ❌ Absent |
| Refinance | ❌ Absent |

> Banner uniquement sur le Calculator. Les 4 autres écrans pourraient aussi en avoir un.

### 8.2 Interstitial

| Paramètre | Valeur |
|---|---|
| Trigger | `AdService.instance.onCalculation()` |
| Déclenché sur | Changement du champ **Home Price** uniquement |
| Seuil | 5 calculs (`calcThreshold = 5`) |
| Cooldown | 5 minutes (`cooldownMinutes = 5`) |

⚠️ **Bug partiel** : `onCalculation()` n'est appelé que sur le champ Home Price dans `calculator_screen.dart:70`. Les changements de taux, terme, et type de prêt ne déclenchent pas le compteur.

### 8.3 Rewarded Ad

| Paramètre | Valeur |
|---|---|
| Durée ad-free | **60 minutes** ✅ (portfolio standard) |
| Persistance | SharedPreferences (`ad_free_until_ms`) |
| Accès | FAB shield (partout) |
| Snackbar confirmation | ✅ "1 hour ad-free unlocked!" |

### 8.4 IAP

✅ **Aucune trace d'IAP dans le code.** Modèle 100% gratuit + AdMob confirmé.

### 8.5 Triggers rewarded supplémentaires

Seul le FAB shield déclenche le rewarded ad. Pas de gate sur : PDF export, historique, partage — ces features sont accessibles gratuitement à tous.

---

## 9. Audit Assets

### 9.1 Images déclarées dans `pubspec.yaml`

```yaml
assets:
  - assets/images/
```

Déclaration de dossier entier — tout fichier dans `assets/images/` est inclus automatiquement.

### 9.2 Icônes Android (Mipmap)

| Densité | ic_launcher.png | ic_launcher_round.png | Status |
|---|---|---|---|
| mdpi (48×48) | ✅ (1 021 bytes) | ✅ | ✅ |
| hdpi (72×72) | ✅ (1 650 bytes) | ✅ | ✅ |
| xhdpi (96×96) | ✅ (2 137 bytes) | ✅ | ✅ |
| xxhdpi (144×144) | ✅ (3 085 bytes) | ✅ | ✅ |
| xxxhdpi (192×192) | ✅ (3 956 bytes) | ✅ | ✅ |
| anydpi-v26 (Adaptive XML) | ✅ `ic_launcher.xml` | ✅ | ✅ |

**✅ Toutes les densités présentes. Adaptive icon Android API 26+ configuré.**

### 9.3 Adaptive Icon (API 26+)

| Fichier | Présent |
|---|---|
| `drawable/ic_launcher_foreground.png` | ✅ |
| `drawable/ic_launcher_background.png` | ✅ |
| `mipmap-anydpi-v26/ic_launcher.xml` | ✅ |
| `mipmap-anydpi-v26/ic_launcher_round.xml` | ✅ |

**✅ Adaptive icon complet.**

### 9.4 Splash screen

| Fichier | Présent |
|---|---|
| `drawable/ic_splash.png` (192×192) | ✅ |
| `drawable/launch_background.xml` | ✅ |
| Splash Flutter (`_SplashWrapper` dans `main.dart`) | ✅ (1 400ms + 400ms fade) |

### 9.5 Icône 512×512 (Play Store)

`docs/CHECKLIST_LAUNCH.md` indique que `icon_512x512.png` **n'a pas encore été redimensionnée** depuis l'icône générée.

### 9.6 Fonts

| Font | Fichier | Poids | Status |
|---|---|---|---|
| Inter | `Inter-Regular.ttf` | 400 | ✅ |
| Inter | `Inter-SemiBold.ttf` | 600 | ✅ |

---

## 10. Audit Permissions

### 10.1 `AndroidManifest.xml` — permissions déclarées

| Permission | Déclarée | Justification | Nécessaire ? |
|---|---|---|---|
| `INTERNET` | ✅ | AdMob, Firebase | ✅ Oui |
| `ACCESS_NETWORK_STATE` | ❌ | — | Recommandée pour AdMob |
| Tout le reste (Location, Camera, Contacts...) | ❌ | — | ✅ Absent = correct |

> **Note :** Google recommande `ACCESS_NETWORK_STATE` pour AdMob (vérifie la connectivité avant de charger). Non bloquant mais bonne pratique.

### 10.2 `AndroidManifest.xml` — meta-data AdMob

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-3940256099942544~3347511713"/>  <!-- TEST ID -->
<meta-data
    android:name="com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT"
    android:value="true"/>  <!-- GDPR compliance ✅ -->
```

**⚠️ App ID encore TEST ID.** À remplacer avant release.

### 10.3 iOS Info.plist

Non audité (nécessite Mac). Points à vérifier manuellement :
- `SKAdNetworkItems` pour AdMob
- `NSUserTrackingUsageDescription` (ATT pour iOS 14.5+)
- `GADApplicationIdentifier` avec vrai App ID

---

## 11. Audit Build

### 11.1 APK Debug

```
✅ flutter build apk --debug
Taille : 210 MB (debug, non optimisé — normal)
Artefact : build/app/outputs/flutter-apk/app-debug.apk
```

### 11.2 AAB Release

```
✅ flutter build appbundle --release
Taille : 44.5 MB (release, minifié)
Artefact : build/app/outputs/bundle/release/app-release.aab
```

### 11.3 Signing Release

`android/app/build.gradle.kts` configure le signing via `android/key.properties` :

```kotlin
val keystorePropsFile = rootProject.file("key.properties")
if (keystorePropsFile.exists()) { /* utilise le keystore */ }
else { signingConfig = signingConfigs.getByName("debug") }  // fallback debug
```

**L'AAB release actuel est signé avec la clé DEBUG** (aucun `key.properties` généré). Non publiable en l'état sur le Play Store.

### 11.4 Minification / Obfuscation

```kotlin
// build.gradle.kts — release buildType
isMinifyEnabled   = true   ✅
isShrinkResources = true   ✅
proguardFiles(
    getDefaultProguardFile("proguard-android-optimize.txt"),
    "proguard-rules.pro"
)
```

**✅ R8/ProGuard activé en release.** Code obfusqué et ressources non utilisées supprimées.

### 11.5 Configuration Android

| Paramètre | Valeur | Status |
|---|---|---|
| `applicationId` | `com.mortgageus.calculator` | ✅ |
| `minSdk` | 24 (Android 7.0) | ✅ Couvre ~96% des appareils |
| `targetSdk` | 34 (Android 14) | ✅ Requis Play Store 2024 |
| `compileSdk` | 36 | ✅ |
| `versionCode` | 1 (`flutter.versionCode`) | ✅ |
| `versionName` | "1.0.0" (`flutter.versionName`) | ✅ |

---

## 12. Audit Sécurité

### 12.1 Clés API / Secrets hardcodés

| Vérification | Résultat |
|---|---|
| Clés API dans le code | ✅ Aucune clé secrète — uniquement les TEST IDs AdMob publics |
| Secrets dans le dépôt | ✅ `key.properties` dans `.gitignore` |
| Mots de passe hardcodés | ✅ Aucun |
| URLs de dev hardcodées | ✅ Aucune |

### 12.2 Logging en production

```dart
// analytics_service.dart
if (kDebugMode) debugPrint('Analytics: $event');  ✅ — debug uniquement
```

✅ Aucun log sensible en production. `0 print()` dans `lib/`.

### 12.3 ProGuard / R8

✅ Activé (voir section 11.4).

### 12.4 Transmission données

L'app ne fait aucune requête réseau propre — uniquement AdMob SDK et (futur) Firebase. Pas de backend propriétaire. Toute la logique de calcul est locale.

### 12.5 Stockage local

`SharedPreferences` utilisé pour :
- `ad_free_until_ms` — timestamp d'expiration de la session ad-free
- `amort_view_yearly` — préférence d'affichage amortissement

Aucune donnée financière personnelle stockée.

---

## 13. Audit Documentation

| Document | Présent | Complet | Problème |
|---|---|---|---|
| `README.md` | ✅ | ❌ | **Flutter boilerplate** — aucune info spécifique au projet |
| `docs/privacy_policy.md` | ✅ | ⚠️ | Email placeholder `[your-support-email@domain.com]` non rempli ; mentionne Firebase comme actif alors qu'il est désactivé |
| `docs/CHECKLIST_LAUNCH.md` | ✅ | ⚠️ | Toutes les étapes en statut "⏳ You must..." — rien de coché |
| `docs/SCREENSHOTS_GUIDE.md` | ✅ | ✅ | Guide présent et détaillé |
| `docs/store-assets/play_store_descriptions.md` | ✅ | ✅ | Descriptions complètes, titre, keywords |
| `CHANGELOG.md` | ❌ | — | Absent |
| `docs/AUDIT_V1_REPORT.md` | Ce fichier | — | — |

### 13.1 Privacy Policy — problèmes détectés

```
⚠️ Ligne ~85 : Contact: [your-support-email@domain.com]
   → Email de support non rempli

⚠️ Section Firebase : mentionne Firebase Analytics + Crashlytics comme collectant des données
   → Or les deux sont désactivés / non intégrés dans le code

⚠️ Pas d'URL publique — la policy doit être hébergée
   (Play Store requiert une URL HTTPS accessible publiquement)
```

---

## 14. Checklist Finale Pré-Publication

| Item | Status | Bloquant ? |
|---|---|---|
| ✅ Tous les tests verts (120/120) | ✅ | — |
| `flutter analyze` : 0 warnings | ❌ (1 warning) | 🟡 |
| Build APK release réussit | ⚠️ (signé debug) | 🔴 |
| Build AAB release réussit | ✅ (44.5 MB, signé debug) | 🔴 Keystore manquant |
| Tous les calculs validés contre source officielle | ✅ | — |
| AdMob IDs test en debug, prod IDs prêts | ❌ IDs TEST partout | 🔴 |
| Firebase configuré | ❌ Non configuré | 🟡 (ou retirer de la privacy policy) |
| Privacy policy rédigée et hébergée | ⚠️ Rédigée, non hébergée, email placeholder | 🔴 (Play Store l'exige) |
| Screenshots réalisés | ❌ 0 screenshots | 🔴 (Play Store l'exige) |
| Play Store descriptions prêtes | ✅ | — |
| Icône toutes tailles Android | ✅ | — |
| Icône 512×512 Play Store | ⚠️ À redimensionner | 🔴 |
| Splash screen configuré | ✅ | — |
| Permissions minimum nécessaires | ✅ | — |
| Aucun IAP accidentel | ✅ | — |
| Dark mode complet | ✅ | — |
| Aucun TODO/FIXME critique | ⚠️ 6 TODOs (AdMob IDs) | 🔴 |
| `dart format` propre | ❌ 24 fichiers | 🟡 |
| `google_mobile_ads` à jour | ❌ v5 vs v8 | 🟡 |
| Keystore de release généré | ❌ | 🔴 |
| Signing config release actif | ❌ | 🔴 |

---

## 15. Recommandations Priorisées

### 🔴 BLOQUANTS — à fixer avant toute soumission au Play Store

1. **Générer le keystore de release** et configurer `android/key.properties`  
   → Sans keystore, l'AAB est signé en debug et rejeté par le Play Store.

2. **Créer les ad units AdMob réels** (3 Android + 3 iOS) et remplacer les 6 TEST IDs dans `ad_config.dart` + l'App ID dans `AndroidManifest.xml`  
   → L'app avec des TEST IDs peut suspendre le compte AdMob.

3. **Héberger la privacy policy** à une URL HTTPS publique  
   → Champ obligatoire dans le Play Console.

4. **Remplir l'email de contact** dans `docs/privacy_policy.md`  
   → `[your-support-email@domain.com]` est un placeholder visible.

5. **Réaliser les screenshots** (minimum 2, idéalement 4-8 pour le Play Store)  
   → Obligatoire pour la publication.

6. **Redimensionner l'icône 512×512** pour le Play Store  
   → Obligatoire pour la fiche Play Store.

7. **Mettre à jour `google_mobile_ads` vers v8.0.0**  
   → 3 majeures de retard, API breaking probable, SDK AdMob obsolète.

---

### 🟡 IMPORTANTS — à traiter si le temps le permet

8. **Supprimer l'import inutilisé** `crashlytics_service.dart` dans `main.dart`  
   → Cause le warning qui fait échouer `flutter analyze` (exit code 1).

9. **Décider de Firebase** : soit l'intégrer correctement (ajouter les packages, `google-services.json`, `flutterfire configure`), soit retirer les mentions de Firebase Analytics/Crashlytics de la privacy policy.

10. **Corriger la duplication** du seuil jumbo `832750.0` dans `mortgage_input.dart` — utiliser `MortgageConstants.conformingLimit1Unit`.

11. **Étendre `AdService.onCalculation()`** aux autres champs (rate, term, loan type) pour que le compteur d'interstitiel soit cohérent avec l'usage réel.

12. **Remplacer tous les `.withOpacity()`** par `.withValues(alpha: ...)` (9 occurrences) pour éliminer les infos de deprecation.

13. **Mettre à jour `riverpod`** de v2 à v3 (breaking — planifier soigneusement).

14. **Corriger le PMI = 0.0** dans `comparator_screen.dart` pour que la comparaison 15yr/30yr soit plus précise.

15. **Exécuter `dart format lib/`** pour normaliser le formatage (commande unique, non-destructive).

---

### 🟢 NICE TO HAVE — post-launch v1.1

16. **Ajouter `BannerAdWidget` sur les 4 autres écrans** (Amortization, Compare, Extra, Refinance) pour maximiser les impressions.

17. **Ajouter des Semantics** pour l'accessibilité (screen readers).

18. **Typer `dynamic` → `MortgageResult?`** dans `_HeroCard` et `_BreakdownCard`.

19. **Ajouter `ACCESS_NETWORK_STATE`** dans AndroidManifest (bonne pratique AdMob).

20. **Customiser `README.md`** avec présentation du projet, setup instructions, architecture.

21. **Créer `CHANGELOG.md`** pour tracker les versions.

22. **Ajouter tests pour `AdFreeService`** et les edge cases non couverts (down payment 100%, overflow).

23. **Permettre des scénarios custom** dans le Comparateur (actuellement hardcodé 15yr vs 30yr).

24. **Supprimer ou justifier `uuid`** si pas utilisé dans `lib/`.

25. **Ajouter haptic feedback** sur les chips de sélection terme/loan type.

---

*Rapport généré automatiquement le 2026-04-14. Lecture seule — aucune modification du code effectuée.*
