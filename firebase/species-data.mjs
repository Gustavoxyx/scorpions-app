/**
 * O catálogo, em um lugar só.
 *
 * Vivia dentro de `seed.mjs`. Saiu de lá quando surgiu um segundo semeador —
 * o da nuvem — porque catálogo duplicado é catálogo que diverge: a correção
 * de um nome científico entraria em um arquivo e não no outro, e o emulador
 * passaria a testar um conteúdo que a produção não tem.
 *
 * As espécies são as mesmas de `lib/data/mock/mock_species.dart`. Enquanto o
 * catálogo real não é curado (Fase 7), este arquivo é a ponte.
 */

const SPECIES = [
  {
    id: 'tityus-serrulatus',
    scientificName: 'Tityus serrulatus',
    commonName: 'Escorpião-amarelo',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'serrulatus',
    summary:
      'Espécie de ampla distribuição no Brasil, reconhecida pela coloração amarelada e pela serrilha nos últimos segmentos da cauda. Descrição resumida para fins de protótipo.',
    sizeRange: '6 a 7 cm de comprimento total',
    coloration: 'Corpo amarelo-claro a amarelo-dourado, com tronco escurecido.',
    behaviour: 'Hábito noturno. Abriga-se em entulhos e frestas.',
    distribution: ['Sudeste', 'Centro-Oeste', 'Nordeste', 'Sul'],
    habitats: ['Áreas urbanas', 'Entulho e construções', 'Mata seca'],
    medicalRelevance: 'significant',
    medicalNotes:
      'Gênero de importância médica reconhecida no Brasil. Acidentes devem ser avaliados por serviço de saúde.',
    accentSeed: 41,
  },
  {
    id: 'tityus-bahiensis',
    scientificName: 'Tityus bahiensis',
    commonName: 'Escorpião-marrom',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'bahiensis',
    summary:
      'Escorpião de coloração escura, comum em áreas de mata e peridomiciliares do Sudeste. Descrição resumida para fins de protótipo.',
    sizeRange: '6 a 7 cm de comprimento total',
    coloration: 'Tronco marrom-escuro; pernas com manchas escuras irregulares.',
    behaviour: 'Noturno e pouco agressivo.',
    distribution: ['Sudeste', 'Centro-Oeste', 'Sul', 'Bahia'],
    habitats: ['Mata atlântica', 'Cerrado', 'Peridomicílio'],
    medicalRelevance: 'significant',
    medicalNotes:
      'Gênero de importância médica reconhecida no Brasil. Acidentes devem ser avaliados por serviço de saúde.',
    accentSeed: 12,
  },
  {
    id: 'tityus-stigmurus',
    scientificName: 'Tityus stigmurus',
    commonName: 'Escorpião-amarelo-do-nordeste',
    family: 'Buthidae',
    genus: 'Tityus',
    specificEpithet: 'stigmurus',
    summary:
      'Predominante no Nordeste, apresenta faixa escura longitudinal no dorso. Descrição resumida para fins de protótipo.',
    sizeRange: '5 a 7 cm de comprimento total',
    coloration: 'Amarelo-claro com listra dorsal escura contínua.',
    behaviour: 'Noturno, frequente em residências e áreas de entulho.',
    distribution: ['Nordeste', 'Norte de Minas Gerais'],
    habitats: ['Caatinga', 'Áreas urbanas', 'Peridomicílio'],
    medicalRelevance: 'significant',
    medicalNotes:
      'Gênero de importância médica reconhecida no Brasil. Acidentes devem ser avaliados por serviço de saúde.',
    accentSeed: 77,
  },
  {
    id: 'bothriurus-bonariensis',
    scientificName: 'Bothriurus bonariensis',
    commonName: 'Escorpião-do-sul',
    family: 'Bothriuridae',
    genus: 'Bothriurus',
    specificEpithet: 'bonariensis',
    summary:
      'Espécie de campos e áreas abertas do Sul do Brasil. Descrição resumida para fins de protótipo.',
    sizeRange: '4 a 6 cm de comprimento total',
    coloration: 'Marrom-avermelhado uniforme.',
    behaviour: 'Vive sob pedras em campos secos.',
    distribution: ['Sul', 'Pampa'],
    habitats: ['Campos', 'Sob pedras'],
    medicalRelevance: 'low',
    medicalNotes: 'Sem registro de acidentes graves na literatura consultada.',
    accentSeed: 129,
  },
  {
    id: 'opisthacanthus-cayaporum',
    scientificName: 'Opisthacanthus cayaporum',
    commonName: 'Escorpião-do-cerrado',
    family: 'Hormuridae',
    genus: 'Opisthacanthus',
    specificEpithet: 'cayaporum',
    summary:
      'Espécie de corpo achatado associada a cascas de árvore do Cerrado. Descrição resumida para fins de protótipo.',
    sizeRange: '5 a 7 cm de comprimento total',
    coloration: 'Marrom-escuro brilhante, com pinças mais avermelhadas.',
    behaviour: 'Vive sob cascas soltas e troncos em decomposição.',
    distribution: ['Centro-Oeste', 'Cerrado'],
    habitats: ['Cerrado', 'Sob cascas'],
    medicalRelevance: 'low',
    medicalNotes: 'Sem relevância médica documentada nas fontes consultadas.',
    accentSeed: 163,
  },
];

const MORPHOLOGY = [
  { name: 'Pedipalpos', description: 'Pinças usadas para capturar a presa.' },
  { name: 'Metassoma (cauda)', description: 'Cinco segmentos móveis.' },
  { name: 'Télson (ferrão)', description: 'Vesícula seguida do acúleo.' },
  { name: 'Pentes', description: 'Estruturas sensoriais ventrais.' },
];

/** Campos que todo documento de espécie recebe, iguais nos dois destinos. */
export function speciesDocuments(now = new Date()) {
  return SPECIES.map(({ id, ...data }) => ({
    id,
    data: {
      ...data,
      morphology: MORPHOLOGY,
      imageUrl: null,
      // Reservado para a Fase 7 (§10, §41). Sempre nulo por enquanto.
      model3dUrl: null,
      createdAt: now,
      updatedAt: now,
    },
  }));
}

export { SPECIES, MORPHOLOGY };
