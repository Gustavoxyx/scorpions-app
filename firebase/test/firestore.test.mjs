import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  deleteDoc,
} from 'firebase/firestore';

import {
  ADMIN,
  ADMIN_EMAIL,
  ALICE,
  ALICE_EMAIL,
  BOB,
  BOB_EMAIL,
  asUser,
  createTestEnv,
  seedContent,
  seedUsers,
} from './helpers.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnv();
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedUsers(testEnv);
  await seedContent(testEnv);
});

// =============================================================================
// users/{uid}
// =============================================================================
describe('users', () => {
  it('a pessoa lê o próprio perfil', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', ALICE)));
  });

  it('a pessoa NÃO lê o perfil de outra', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDoc(doc(db, 'users', BOB)));
  });

  it('quem não está autenticado não lê perfil algum', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users', ALICE)));
  });

  it('a pessoa NÃO enumera a base de usuários', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDocs(collection(db, 'users')));
  });

  it('admin lê o perfil de outra pessoa', async () => {
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', ALICE)));
  });

  it('cria o próprio documento no cadastro', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', ALICE), {
        uid: ALICE,
        name: 'Alice',
        email: ALICE_EMAIL,
        role: 'user',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NÃO cria documento com uid de outra pessoa', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', BOB), {
        uid: BOB,
        name: 'Impostora',
        email: BOB_EMAIL,
        role: 'user',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  // O cenário de escalação de privilégio: o cliente adulterado tenta nascer
  // administrador. A regra fixa `role` em 'user' na criação.
  it('NÃO se cadastra já como admin', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', ALICE), {
        uid: ALICE,
        name: 'Alice',
        email: ALICE_EMAIL,
        role: 'admin',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NÃO se cadastra com e-mail diferente do token', async () => {
    await testEnv.clearFirestore();
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', ALICE), {
        uid: ALICE,
        name: 'Alice',
        email: 'outro@exemplo.test',
        role: 'user',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('altera o próprio nome', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', ALICE), {
        name: 'Alice Nunes',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  // A segunda porta da escalação: já cadastrada, tenta se promover.
  it('NÃO se promove a admin depois de cadastrada', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', ALICE), {
        role: 'admin',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NÃO altera o próprio e-mail pelo documento', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', ALICE), {
        email: 'novo@exemplo.test',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NÃO apaga o próprio documento pelo aplicativo', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(deleteDoc(doc(db, 'users', ALICE)));
  });
});

// =============================================================================
// species/{id}
// =============================================================================
describe('species', () => {
  it('o catálogo é legível sem autenticação', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'species', 'tityus-serrulatus')));
  });

  it('a pessoa NÃO altera uma espécie', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'species', 'tityus-serrulatus'), {
        commonName: 'Nome inventado',
      }),
    );
  });

  it('a pessoa NÃO cria uma espécie', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'species', 'especie-falsa'), {
        scientificName: 'Fake species',
      }),
    );
  });

  it('admin altera uma espécie', async () => {
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'species', 'tityus-serrulatus'), {
        commonName: 'Escorpião-amarelo',
      }),
    );
  });
});

// =============================================================================
// identifications/{id}
// =============================================================================
describe('identifications', () => {
  const validDoc = (userId) => ({
    userId,
    imageUrl: null,
    status: 'identified',
    modelVersion: 'mock-v1',
    isMock: true,
    confidence: 0.9,
    speciesId: 'tityus-serrulatus',
    scientificName: 'Tityus serrulatus',
    createdAt: serverTimestamp(),
  });

  it('cria uma identificação própria', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'identifications', 'nova-1'), validDoc(ALICE)),
    );
  });

  it('NÃO cria identificação em nome de outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'nova-2'), validDoc(BOB)),
    );
  });

  it('NÃO cria com status inválido', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'nova-3'), {
        ...validDoc(ALICE),
        status: 'aprovado_por_mim',
      }),
    );
  });

  it('NÃO cria com confiança fora de 0..1', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'nova-4'), {
        ...validDoc(ALICE),
        confidence: 42,
      }),
    );
  });

  it('lê a própria identificação', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(getDoc(doc(db, 'identifications', 'id-alice-1')));
  });

  it('NÃO lê a identificação de outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDoc(doc(db, 'identifications', 'id-bob-1')));
  });

  // Brief §28: nunca buscar o histórico de todos. A regra transforma isso em
  // garantia do servidor — a consulta sem filtro é recusada.
  it('NÃO lista o histórico sem filtrar por userId', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDocs(collection(db, 'identifications')));
  });

  it('lista o próprio histórico quando filtra por userId', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      getDocs(
        query(collection(db, 'identifications'), where('userId', '==', ALICE)),
      ),
    );
  });

  it('NÃO lista o histórico alheio filtrando pelo uid da outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      getDocs(
        query(collection(db, 'identifications'), where('userId', '==', BOB)),
      ),
    );
  });

  it('NÃO transfere a própria identificação para outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'identifications', 'id-alice-1'), { userId: BOB }),
    );
  });

  it('apaga a própria identificação', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(deleteDoc(doc(db, 'identifications', 'id-alice-1')));
  });

  it('NÃO apaga a identificação de outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(deleteDoc(doc(db, 'identifications', 'id-bob-1')));
  });

  it('quem não está autenticado não cria nada', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'anon-1'), validDoc(ALICE)),
    );
  });
});

// =============================================================================
// Coleções não previstas
// =============================================================================
describe('negação final', () => {
  it('NÃO escreve numa coleção arbitrária', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'colecao_inventada', 'x'), { qualquer: 'coisa' }),
    );
  });

  it('nem o admin escreve numa coleção arbitrária', async () => {
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'audit_logs', 'x'), { acao: 'teste' }),
    );
  });
});
