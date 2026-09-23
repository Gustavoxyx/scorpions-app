import '../models/captured_image.dart';
import '../models/identification.dart';
import 'mock_species.dart';

/// ============================================================================
/// DADOS SIMULADOS — FASE 1
/// ============================================================================
/// Histórico pré-carregado para que a aba correspondente não nasça vazia. Na
/// Fase 3 este arquivo some e o `IdentificationRepository` passa a consultar a
/// coleção `identifications` do usuário no Firestore.
/// ============================================================================
abstract final class MockHistory {
  static DateTime _daysAgo(int days, {int hour = 14, int minute = 20}) {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute)
        .subtract(Duration(days: days));
  }

  static CapturedImage _image(int days) => CapturedImage(
        source: ImageSource.simulated,
        capturedAt: _daysAgo(days),
      );

  static List<IdentificationResult> seed() => <IdentificationResult>[
        IdentificationResult.identified(
          id: 'mock-hist-1',
          image: _image(1),
          createdAt: _daysAgo(1, hour: 19, minute: 42),
          isMock: true,
          predictions: <SpeciesPrediction>[
            SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.94),
            SpeciesPrediction(species: MockSpecies.tityusStigmurus, score: 0.04),
          ],
        ),
        IdentificationResult.identified(
          id: 'mock-hist-2',
          image: _image(4),
          createdAt: _daysAgo(4, hour: 8, minute: 5),
          isMock: true,
          predictions: <SpeciesPrediction>[
            SpeciesPrediction(species: MockSpecies.tityusBahiensis, score: 0.72),
            SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.19),
          ],
        ),
        IdentificationResult.rejected(
          id: 'mock-hist-3',
          image: _image(9),
          createdAt: _daysAgo(9, hour: 22, minute: 11),
          isMock: true,
          reason: RejectionReason.lowImageQuality,
        ),
        IdentificationResult.identified(
          id: 'mock-hist-4',
          image: _image(16),
          createdAt: _daysAgo(16, hour: 11, minute: 30),
          isMock: true,
          predictions: <SpeciesPrediction>[
            SpeciesPrediction(
                species: MockSpecies.bothriurusBonariensis, score: 0.58),
            SpeciesPrediction(
                species: MockSpecies.opisthacanthusCayaporum, score: 0.21),
          ],
        ),
      ];
}
