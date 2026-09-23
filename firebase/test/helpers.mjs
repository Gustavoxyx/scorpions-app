import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

const here = dirname(fileURLToPath(import.meta.url));
const firebaseDir = join(here, '..');

/** Identidades usadas pelos cenários do brief §21. */
export const ALICE = 'uid-alice';
export const BOB = 'uid-bob';
export const ADMIN = 'uid-admin';

export const ALICE_EMAIL = 'alice@exemplo.test';
export const BOB_EMAIL = 'bob@exemplo.test';
export const ADMIN_EMAIL = 'admin@exemplo.test';

/**
 * Sobe o ambiente de teste contra os emuladores.
 *
 * O `projectId` começa com `demo-` de propósito: projetos com esse prefixo
 * nunca alcançam a nuvem, mesmo que alguma credencial esteja presente na
 * máquina. É a salvaguarda contra rodar um teste destrutivo em produção
 * (brief §20).
 */
export async function createTestEnv() {
  return initializeTestEnvironment({
    projectId: 'demo-scorpions',
    firestore: {
      rules: readFileSync(join(firebaseDir, 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync(join(firebaseDir, 'storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
}

/**
 * Semeia os documentos de usuário sem passar pelas regras.
 *
 * `withSecurityRulesDisabled` existe justamente para preparar o estado: sem
 * ele, seria impossível criar um admin — as regras (corretamente) proíbem que
 * qualquer cliente se promova.
 */
export async function seedUsers(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`users/${ALICE}`).set({
      uid: ALICE,
      name: 'Alice',
      email: ALICE_EMAIL,
      role: 'user',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`users/${BOB}`).set({
      uid: BOB,
      name: 'Bob',
      email: BOB_EMAIL,
      role: 'user',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.doc(`users/${ADMIN}`).set({
      uid: ADMIN,
      name: 'Admin',
      email: ADMIN_EMAIL,
      role: 'admin',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

/** Semeia uma espécie e uma identificação pertencente à Alice. */
export async function seedContent(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('species/tityus-serrulatus').set({
      scientificName: 'Tityus serrulatus',
      commonName: 'Escorpião-amarelo',
      family: 'Buthidae',
    });
    await db.doc('identifications/id-alice-1').set({
      userId: ALICE,
      status: 'identified',
      modelVersion: 'mock-v1',
      confidence: 0.94,
      speciesId: 'tityus-serrulatus',
      createdAt: new Date(),
    });
    await db.doc('identifications/id-bob-1').set({
      userId: BOB,
      status: 'identified',
      modelVersion: 'mock-v1',
      confidence: 0.8,
      speciesId: 'tityus-serrulatus',
      createdAt: new Date(),
    });
  });
}

/** Contexto autenticado com o e-mail no token (as regras conferem `email`). */
export function asUser(testEnv, uid, email) {
  return testEnv.authenticatedContext(uid, { email, email_verified: true });
}

/** Bytes de um PNG 1x1 válido, para os testes de upload. */
export const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);
