/**
 * Popula o emulador com o catálogo de espécies.
 *
 * Uso:
 *   npm run seed          (com os emuladores já rodando)
 *
 * As espécies são as mesmas de `lib/data/mock/mock_species.dart`. Enquanto o
 * catálogo real não é curado (Fase 7), este arquivo é a ponte: o aplicativo em
 * modo `emulator` lê do Firestore e vê o mesmo conteúdo que via em memória.
 *
 * -----------------------------------------------------------------------------
 * POR QUE ELE USA `withSecurityRulesDisabled`
 * -----------------------------------------------------------------------------
 * Semear o catálogo é operação administrativa: as regras exigem `role: 'admin'`
 * para escrever em `species`, e é assim que deve ser. A primeira versão deste
 * script usava o SDK cliente comum e foi corretamente recusada com
 * PERMISSION_DENIED — o que é uma boa notícia sobre as regras.
 *
 * `initializeTestEnvironment` é a ferramenta certa aqui, e tem uma propriedade
 * valiosa: ela **só conversa com emuladores**. Não existe caminho pelo qual
 * este script alcance um banco de produção, nem por engano. E não precisa de
 * service account, o que mantém o §32 intacto: nenhuma credencial no projeto.
 */
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

/** Subconjunto do catálogo. O conteúdo completo vive no app. */
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

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-scorpions',
  firestore: {
    rules: readFileSync(join(here, 'firestore.rules'), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  const now = new Date();

  for (const { id, ...data } of SPECIES) {
    await db.doc(`species/${id}`).set({
      ...data,
      morphology: MORPHOLOGY,
      imageUrl: null,
      // Reservado para a Fase 7 (§10, §41). Sempre nulo por enquanto.
      model3dUrl: null,
      createdAt: now,
      updatedAt: now,
    });
  }
});

await testEnv.cleanup();

console.log(`Catálogo semeado: ${SPECIES.length} espécies em demo-scorpions.`);
process.exit(0);
