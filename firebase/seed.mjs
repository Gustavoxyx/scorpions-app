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

import { speciesDocuments } from './species-data.mjs';

const here = dirname(fileURLToPath(import.meta.url));

/** Subconjunto do catálogo. O conteúdo completo vive no app. */

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-scorpions',
  firestore: {
    rules: readFileSync(join(here, 'firestore.rules'), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

const docs = speciesDocuments();

await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  for (const { id, data } of docs) {
    await db.doc(`species/${id}`).set(data);
  }
});

await testEnv.cleanup();

console.log(`Catálogo semeado: ${docs.length} espécies em demo-scorpions.`);
process.exit(0);
