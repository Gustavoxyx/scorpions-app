import '../models/species.dart';

/// ============================================================================
/// DADOS SIMULADOS — FASE 1
/// ============================================================================
/// Este arquivo é a ÚNICA origem de espécies do protótipo. O conteúdo é uma
/// aproximação didática baseada em espécies reais e NÃO tem validade
/// científica: não foi revisado por especialista, não cita fontes e não deve
/// ser usado para decisão médica ou taxonômica.
///
/// Na Fase 7 este arquivo é apagado e o `SpeciesRepository` passa a ler a
/// coleção `species` do Firestore, curada com referências. A UI não muda.
/// ============================================================================
abstract final class MockSpecies {
  static MorphologyFeature _f(String name, String description) =>
      MorphologyFeature(name: name, description: description);

  static const String _fabricationNotice =
      'Descrição resumida para fins de protótipo.';

  static final Species tityusSerrulatus = Species(
    id: 'tityus-serrulatus',
    scientificName: 'Tityus serrulatus',
    commonName: 'Escorpião-amarelo',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'serrulatus',
    accentSeed: 41,
    summary:
        'Espécie de ampla distribuição no Brasil, reconhecida pela coloração '
        'amarelada e pela serrilha característica nos últimos segmentos da '
        'cauda. Reproduz-se por partenogênese, o que favorece sua expansão '
        'em áreas urbanas. $_fabricationNotice',
    sizeRange: '6 a 7 cm de comprimento total',
    coloration:
        'Corpo amarelo-claro a amarelo-dourado, com tronco escurecido e '
        'pernas mais claras.',
    behaviour:
        'Hábito noturno. Abriga-se em entulhos, frestas e galerias de esgoto. '
        'Foge do contato e só usa o ferrão quando pressionado.',
    distribution: <String>['Sudeste', 'Centro-Oeste', 'Nordeste', 'Sul'],
    habitats: <String>['Áreas urbanas', 'Entulho e construções', 'Mata seca'],
    medicalRelevance: MedicalRelevance.significant,
    medicalNotes:
        'Gênero de importância médica reconhecida no Brasil. Acidentes devem '
        'ser avaliados por serviço de saúde.',
    morphology: <MorphologyFeature>[
      _f('Pedipalpos',
          'Pinças finas e alongadas, com dedos delgados — padrão típico dos butídeos.'),
      _f('Metassoma (cauda)',
          'Cinco segmentos; os dois últimos apresentam serrilha dorsal, sinal diagnóstico da espécie.'),
      _f('Télson (ferrão)',
          'Vesícula arredondada seguida de acúleo curvo, com tubérculo subaculear discreto.'),
      _f('Pentes',
          'Estruturas sensoriais ventrais usadas para reconhecer o substrato; contagem de dentes auxilia na identificação.'),
    ],
  );

  static final Species tityusBahiensis = Species(
    id: 'tityus-bahiensis',
    scientificName: 'Tityus bahiensis',
    commonName: 'Escorpião-marrom',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'bahiensis',
    accentSeed: 12,
    summary:
        'Escorpião de coloração escura, comum em áreas de mata e em ambientes '
        'peridomiciliares do Sudeste e Centro-Oeste. Distingue-se do '
        'escorpião-amarelo pelas manchas escuras nas pernas. $_fabricationNotice',
    sizeRange: '6 a 7 cm de comprimento total',
    coloration:
        'Tronco marrom-escuro; pernas e pedipalpos com manchas escuras '
        'irregulares sobre fundo mais claro.',
    behaviour:
        'Noturno e pouco agressivo. Encontrado sob troncos, pedras e material '
        'de construção acumulado.',
    distribution: <String>['Sudeste', 'Centro-Oeste', 'Sul', 'Bahia'],
    habitats: <String>['Mata atlântica', 'Cerrado', 'Peridomicílio'],
    medicalRelevance: MedicalRelevance.significant,
    medicalNotes:
        'Gênero de importância médica reconhecida no Brasil. Acidentes devem '
        'ser avaliados por serviço de saúde.',
    morphology: <MorphologyFeature>[
      _f('Pedipalpos', 'Pinças escuras, com manchas contrastantes nos dedos.'),
      _f('Metassoma (cauda)',
          'Segmentos robustos e sem serrilha evidente nos dois últimos anéis.'),
      _f('Télson (ferrão)', 'Vesícula alongada com acúleo bem curvado.'),
      _f('Pernas',
          'Padrão manchado nas tíbias — o traço mais útil para separar da espécie amarela.'),
    ],
  );

  static final Species tityusStigmurus = Species(
    id: 'tityus-stigmurus',
    scientificName: 'Tityus stigmurus',
    commonName: 'Escorpião-amarelo-do-nordeste',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'stigmurus',
    accentSeed: 77,
    summary:
        'Predominante no Nordeste brasileiro, apresenta faixa escura '
        'longitudinal no dorso e um triângulo escuro na região cefálica. '
        'Adapta-se bem ao ambiente urbano. $_fabricationNotice',
    sizeRange: '5 a 7 cm de comprimento total',
    coloration:
        'Amarelo-claro com listra dorsal escura contínua e mancha triangular '
        'no prossoma.',
    behaviour:
        'Noturno, frequente em residências, muros e áreas de entulho do '
        'semiárido.',
    distribution: <String>['Nordeste', 'Norte de Minas Gerais'],
    habitats: <String>['Caatinga', 'Áreas urbanas', 'Peridomicílio'],
    medicalRelevance: MedicalRelevance.significant,
    medicalNotes:
        'Gênero de importância médica reconhecida no Brasil. Acidentes devem '
        'ser avaliados por serviço de saúde.',
    morphology: <MorphologyFeature>[
      _f('Prossoma', 'Mancha triangular escura bem delimitada na região ocular.'),
      _f('Mesossoma', 'Faixa escura longitudinal percorrendo os tergitos.'),
      _f('Metassoma (cauda)', 'Segmentos claros com quilhas granulosas discretas.'),
      _f('Télson (ferrão)', 'Vesícula clara com tubérculo subaculear presente.'),
    ],
  );

  static final Species tityusObscurus = Species(
    id: 'tityus-obscurus',
    scientificName: 'Tityus obscurus',
    commonName: 'Escorpião-preto-da-amazônia',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'obscurus',
    accentSeed: 5,
    summary:
        'Espécie amazônica de coloração muito escura, associada a áreas de '
        'floresta e a plantações. Adultos podem ser quase negros, enquanto '
        'jovens exibem padrão manchado. $_fabricationNotice',
    sizeRange: '7 a 9 cm de comprimento total',
    coloration:
        'Marrom muito escuro a quase preto nos adultos; jovens com manchas '
        'claras nos pedipalpos e nas pernas.',
    behaviour:
        'Noturno, abriga-se sob folhas caídas, cascas e palhas. Comum em '
        'áreas de extrativismo.',
    distribution: <String>['Norte', 'Amazônia Oriental'],
    habitats: <String>['Floresta amazônica', 'Plantações', 'Serrapilheira'],
    medicalRelevance: MedicalRelevance.significant,
    medicalNotes:
        'Gênero de importância médica reconhecida no Brasil. Acidentes devem '
        'ser avaliados por serviço de saúde.',
    morphology: <MorphologyFeature>[
      _f('Pedipalpos', 'Pinças robustas e escuras, com granulação marcada.'),
      _f('Metassoma (cauda)', 'Segmentos alongados, uniformemente escuros.'),
      _f('Télson (ferrão)', 'Vesícula volumosa, mais alta que nas congêneres do Sudeste.'),
      _f('Coloração juvenil', 'Padrão manchado que desaparece com as mudas.'),
    ],
  );

  static final Species bothriurusBonariensis = Species(
    id: 'bothriurus-bonariensis',
    scientificName: 'Bothriurus bonariensis',
    commonName: 'Escorpião-do-sul',
    family: 'Bothriuridae',
    genus: 'Bothriurus',
    specificEpithet: 'bonariensis',
    accentSeed: 129,
    summary:
        'Espécie de campos e áreas abertas do Sul do Brasil, Uruguai e '
        'Argentina. Difere dos butídeos pelo télson sem tubérculo subaculear '
        'e pelo corpo mais achatado. $_fabricationNotice',
    sizeRange: '4 a 6 cm de comprimento total',
    coloration: 'Marrom-avermelhado uniforme, com cauda ligeiramente mais clara.',
    behaviour:
        'Vive sob pedras em campos secos. Pouco associado a ambientes '
        'domésticos.',
    distribution: <String>['Sul', 'Pampa', 'Sudeste litorâneo'],
    habitats: <String>['Campos', 'Costões e afloramentos', 'Sob pedras'],
    medicalRelevance: MedicalRelevance.low,
    medicalNotes:
        'Sem registro de acidentes graves na literatura consultada para este '
        'protótipo.',
    morphology: <MorphologyFeature>[
      _f('Télson (ferrão)', 'Sem tubérculo subaculear — separa a família Bothriuridae dos butídeos.'),
      _f('Pedipalpos', 'Pinças largas e achatadas.'),
      _f('Metassoma (cauda)', 'Curta em relação ao corpo, de aspecto robusto.'),
      _f('Corpo', 'Perfil dorsoventral achatado, adaptado a fendas de rocha.'),
    ],
  );

  static final Species rhopalurusRochai = Species(
    id: 'rhopalurus-rochai',
    scientificName: 'Rhopalurus rochai',
    commonName: 'Escorpião-vermelho-da-caatinga',
    family: 'Buthidae',
    genus: 'Rhopalurus',
    specificEpithet: 'rochai',
    accentSeed: 208,
    summary:
        'Endêmico do semiárido nordestino, chama atenção pelo contraste entre '
        'o tronco escuro e a cauda avermelhada. Ocupa afloramentos rochosos e '
        'solos arenosos. $_fabricationNotice',
    sizeRange: '5 a 7 cm de comprimento total',
    coloration:
        'Tronco escuro com reticulado claro; metassoma e pedipalpos '
        'avermelhados.',
    behaviour:
        'Noturno; escava abrigos rasos em solo arenoso. Estridula ao ser '
        'perturbado.',
    distribution: <String>['Nordeste', 'Caatinga'],
    habitats: <String>['Solo arenoso', 'Afloramentos rochosos'],
    medicalRelevance: MedicalRelevance.moderate,
    medicalNotes:
        'Acidentes descritos com sintomas geralmente locais. Avaliação '
        'médica continua indicada.',
    morphology: <MorphologyFeature>[
      _f('Metassoma (cauda)', 'Coloração avermelhada contrastante com o tronco.'),
      _f('Pentes', 'Bem desenvolvidos, com alto número de dentes.'),
      _f('Órgão estridulador', 'Área rugosa no mesossoma usada para produzir som de alerta.'),
      _f('Pedipalpos', 'Dedos alongados e finos.'),
    ],
  );

  static final Species opisthacanthusCayaporum = Species(
    id: 'opisthacanthus-cayaporum',
    scientificName: 'Opisthacanthus cayaporum',
    commonName: 'Escorpião-do-cerrado',
    family: 'Hormuridae',
    genus: 'Opisthacanthus',
    specificEpithet: 'cayaporum',
    accentSeed: 163,
    summary:
        'Espécie de corpo achatado associada a cascas de árvore e cupinzeiros '
        'do Cerrado. Pinças notavelmente largas em comparação com a cauda '
        'curta. $_fabricationNotice',
    sizeRange: '5 a 7 cm de comprimento total',
    coloration: 'Marrom-escuro brilhante, com pinças mais avermelhadas.',
    behaviour:
        'Vive sob cascas soltas e em troncos em decomposição. Movimentos '
        'lentos e comportamento discreto.',
    distribution: <String>['Centro-Oeste', 'Cerrado', 'Norte de São Paulo'],
    habitats: <String>['Cerrado', 'Sob cascas', 'Troncos em decomposição'],
    medicalRelevance: MedicalRelevance.low,
    medicalNotes:
        'Sem relevância médica documentada nas fontes consultadas para este '
        'protótipo.',
    morphology: <MorphologyFeature>[
      _f('Pedipalpos', 'Pinças largas e achatadas, muito maiores que a cauda.'),
      _f('Metassoma (cauda)', 'Curta e delgada em relação ao corpo.'),
      _f('Corpo', 'Achatamento acentuado, adaptado a viver sob cascas.'),
      _f('Télson (ferrão)', 'Vesícula pequena, sem tubérculo subaculear.'),
    ],
  );

  static final Species ananterisBalzanii = Species(
    id: 'ananteris-balzanii',
    scientificName: 'Ananteris balzanii',
    commonName: 'Escorpião-anão',
    family: 'Buthidae',
    genus: 'Ananteris',
    specificEpithet: 'balzanii',
    accentSeed: 96,
    summary:
        'Escorpião de porte muito pequeno, com padrão manchado que se confunde '
        'com folhas secas. Conhecido pela autotomia da cauda: pode perder os '
        'últimos segmentos para escapar de predadores. $_fabricationNotice',
    sizeRange: '2 a 3,5 cm de comprimento total',
    coloration:
        'Amarelo-palha com manchas escuras irregulares em todo o corpo.',
    behaviour:
        'Vive na serrapilheira do Cerrado e do Pantanal. Difícil de avistar '
        'pelo tamanho e pela camuflagem.',
    distribution: <String>['Centro-Oeste', 'Pantanal', 'Cerrado'],
    habitats: <String>['Serrapilheira', 'Solo arenoso'],
    medicalRelevance: MedicalRelevance.low,
    medicalNotes:
        'Sem relevância médica documentada nas fontes consultadas para este '
        'protótipo.',
    morphology: <MorphologyFeature>[
      _f('Tamanho', 'Um dos menores escorpiões brasileiros — raramente ultrapassa 3,5 cm.'),
      _f('Metassoma (cauda)', 'Capaz de autotomia: os segmentos finais se desprendem.'),
      _f('Coloração', 'Padrão manchado de alta camuflagem sobre folhas secas.'),
      _f('Pedipalpos', 'Pinças delicadas e finas.'),
    ],
  );

  /// Catálogo completo do protótipo, na ordem em que aparece na aba Catálogo.
  static final List<Species> all = <Species>[
    tityusSerrulatus,
    tityusBahiensis,
    tityusStigmurus,
    tityusObscurus,
    rhopalurusRochai,
    bothriurusBonariensis,
    opisthacanthusCayaporum,
    ananterisBalzanii,
  ];

  static Species? byId(String id) {
    for (final Species s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}
