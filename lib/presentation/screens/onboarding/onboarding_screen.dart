import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
        appKey: 'mortgageus',
        onDone: () => Navigator.of(context).pushReplacementNamed('/home'),
        pages: const [
          OnboardingPage(
            icon: Icons.home_rounded,
            title: 'Your Smart\nMortgage Calculator',
            subtitle:
                'Monthly payment, amortization & property breakdown — all in one place.',
            pills: ['Spanish/Español', 'FHA·VA·USDA', 'DTI Calc', '51 States'],
            titleFr: 'Votre calculatrice\nhypothécaire',
            subtitleFr:
                'Versement mensuel, amortissement et bilan immobilier — tout en un.',
            pillsFr: ['Spanish/Español', 'FHA·VA·USDA', 'Calcul DTI', '51 États'],
            titleEs: 'Tu calculadora\nhipotecaria',
            subtitleEs:
                'Pago mensual, amortización y análisis de propiedad — todo en uno.',
            pillsEs: ['Spanish/Español', 'FHA·VA·USDA', 'Calc. DTI', '51 Estados'],
          ),
          OnboardingPage(
            icon: Icons.bar_chart_rounded,
            title: 'Compare Loan\nScenarios',
            subtitle:
                'Switch between 15yr and 30yr or fixed vs adjustable — instantly.',
            pills: ['Fixed Rate', 'ARM', '15 vs 30 Year'],
            titleFr: 'Comparez les\nscénarios',
            subtitleFr:
                'Passez de 15 à 30 ans ou taux fixe vs variable — instantanément.',
            pillsFr: ['Taux fixe', 'ARM', '15 vs 30 ans'],
            titleEs: 'Compara\nescenarios',
            subtitleEs:
                'Cambia entre 15 y 30 años o tasa fija vs variable — al instante.',
            pillsEs: ['Tasa fija', 'ARM', '15 vs 30 años'],
          ),
          OnboardingPage(
            icon: Icons.history_rounded,
            title: 'Save Every\nScenario',
            subtitle:
                'Your calculations are saved automatically. Revisit and compare anytime.',
            pills: ['History', 'PDF Export', 'Share'],
            titleFr: 'Sauvegardez vos\nscénarios',
            subtitleFr:
                'Vos calculs sont sauvegardés automatiquement. Retrouvez-les et comparez.',
            pillsFr: ['Historique', 'Export PDF', 'Partager'],
            titleEs: 'Guarda todos\ntus escenarios',
            subtitleEs:
                'Tus cálculos se guardan automáticamente. Recupéralos y compara cuando quieras.',
            pillsEs: ['Historial', 'Exportar PDF', 'Compartir'],
          ),
        ],
      );
}
