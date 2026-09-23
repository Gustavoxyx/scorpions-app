import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, describe, it } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

import {
  ADMIN,
  ADMIN_EMAIL,
  ALICE,
  ALICE_EMAIL,
  BOB,
  asUser,
  createTestEnv,
  seedUsers,
} from './helpers.mjs';

/**
 * Testes de CONTRATO entre o aplicativo e as regras.
 *
 * Enquanto `firestore.test.mjs` verifica a *política* ("Alice não lê o
 * documento de Bob") com documentos escritos à mão, este arquivo verifica a
 * *compatibilidade*: as formas exatas que o código Dart grava passam pelas
 * regras?
 *
 * Ele existe porque essa distinção custou um bug real. O mapa de criação de
 * usuário não trazia `role`, a regra exigia `role == 'user'`, e nenhum teste
 * percebeu — porque todos inventavam o documento em vez de usar o de verdade.
 *
 * As formas vêm de `contract-shapes.json`, gerado por
 * `test/contract_shapes_test.dart`. Se ele estiver ausente, rode antes:
 *
 *     flutter test test/contract_shapes_test.dart
 */
const here = dirname(fileURLToPath(import.meta.url));
const shapesPath = join(here, 'contract-shapes.json');

/** Troca a sentinela exportada pelo Dart pelo carimbo real do Firestore. */
function hydrate(value) {
  if (value === '__SERVER_TIMESTAMP__') return serverTimestamp();
  if (Array.isArray(value)) return value.map(hydrate);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, hydrate(v)]),
    );
  }
  return value;
}

let testEnv;
let shapes;

before(async () => {
  shapes = JSON.parse(readFileSync(shapesPath, 'utf8'));
  testEnv = await createTestEnv();
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedUsers(testEnv);
});

describe('contrato: formas geradas pelo aplicativo', () => {
  // O teste que teria pego o bug do `role` ausente.
  it('o cadastro que o app envia é aceito pelas regras', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', ALICE), hydrate(shapes.userCreate)),
    );
  });

  it('a atualização de perfil que o app envia é aceita', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', ALICE), hydrate(shapes.userUpdate)),
    );
  });

  it('a identificação que o app grava é aceita', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'identifications', 'ident-1'),
        hydrate(shapes.identificationIdentified),
      ),
    );
  });

  it('a rejeição que o app grava é aceita', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'identifications', 'ident-2'),
        hydrate(shapes.identificationRejected),
      ),
    );
  });

  it('a espécie que o app serializa é aceita por um admin', async () => {
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'species', 'tityus-serrulatus'), hydrate(shapes.species)),
    );
  });

  // A mesma forma real, agora com intenção maliciosa: continua barrada.
  it('a mesma forma com userId de outra pessoa é recusada', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'ident-3'), {
        ...hydrate(shapes.identificationIdentified),
        userId: BOB,
      }),
    );
  });

  it('a mesma forma de cadastro com role admin é recusada', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', ALICE), {
        ...hydrate(shapes.userCreate),
        role: 'admin',
      }),
    );
  });

  it('a espécie que o app serializa é recusada para usuário comum', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'species', 'tityus-serrulatus'), hydrate(shapes.species)),
    );
  });
});
