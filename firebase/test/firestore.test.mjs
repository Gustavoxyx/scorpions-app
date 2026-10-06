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
  // O que o CLIENTE tem direito de gravar.
  //
  // Repare no que não está aqui: `confidence`, `speciesId`, `scientificName`,
  // `modelVersion`. Eles saíram deste documento quando a auditoria (HIGH-1)
  // mostrou que a regra validava o FORMATO de `confidence` e deixava passar
  // qualquer valor entre 0 e 1 — um `0.99` forjado passava igual a um
  // produzido por modelo.
  //
  // Esta forma espelha `IdentificationResult.toClientCreateMap()` no Dart, e
  // o teste de contrato confere que as duas continuam iguais.
  const validDoc = (userId) => ({
    userId,
    imageUrl: null,
    status: 'processing',
    pipelineVersion: 'pipeline-v1',
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

  // ---------------------------------------------------------------------------
  // A segunda fotografia (Fase 5)
  // ---------------------------------------------------------------------------
  const segundaVista = () => ({
    captureType: 'tail',
    instructionId: 'secondary-tail',
    imageUrl: null,
    thumbnailUrl: null,
    imageQuality: { quality: 'good', score: 0.81 },
  });

  it('cria uma identificação com duas vistas', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'identifications', 'duas-1'), {
        ...validDoc(ALICE),
        viewCount: 2,
        secondaryView: segundaVista(),
      }),
    );
  });

  it('NÃO esconde conclusão de análise dentro da segunda vista', async () => {
    // O teste que justifica o `hasOnly` na regra.
    //
    // `serverOwnedFields()` olha as chaves do documento. Um mapa aninhado
    // aberto seria o lugar óbvio para um cliente adulterado guardar
    // `confidence: 0.99` um nível abaixo de onde a regra confere.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    for (const extra of [
      { confidence: 0.99 },
      { speciesId: 'tityus-serrulatus' },
      { agreeOnTop1: true },
      { qualquerCoisa: 'x' },
    ]) {
      await assertFails(
        setDoc(doc(db, 'identifications', 'duas-forjada'), {
          ...validDoc(ALICE),
          viewCount: 2,
          secondaryView: { ...segundaVista(), ...extra },
        }),
      );
    }
  });

  it('NÃO cria com `fusion` — o que as vistas disseram juntas é do servidor', async () => {
    // Forjar "as duas fotos concordaram" é o mesmo ataque de forjar
    // `confidence: 0.99`, por outro campo.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'duas-fusion'), {
        ...validDoc(ALICE),
        viewCount: 2,
        secondaryView: segundaVista(),
        fusion: { agreeOnTop1: true, decisionLevel: 'high_confidence' },
      }),
    );
  });

  it('NÃO declara três vistas', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    for (const n of [0, 3, 99, -1, '2']) {
      await assertFails(
        setDoc(doc(db, 'identifications', 'duas-n'), {
          ...validDoc(ALICE),
          viewCount: n,
        }),
      );
    }
  });

  it('NÃO aceita segunda vista com forma errada', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    for (const ruim of [
      'tail',
      ['tail'],
      { ...segundaVista(), captureType: 42 },
      { ...segundaVista(), captureType: 'x'.repeat(33) },
      { ...segundaVista(), imageUrl: 'x'.repeat(513) },
      { ...segundaVista(), imageQuality: 'boa' },
    ]) {
      await assertFails(
        setDoc(doc(db, 'identifications', 'duas-ruim'), {
          ...validDoc(ALICE),
          viewCount: 2,
          secondaryView: ruim,
        }),
      );
    }
  });

  it('anexa os caminhos da segunda vista depois do envio', async () => {
    // O segundo passo normal do pipeline: o registro nasce sem imagem e recebe
    // os caminhos quando o envio termina.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    const ref = doc(db, 'identifications', 'duas-2');
    await setDoc(ref, {
      ...validDoc(ALICE),
      viewCount: 2,
      secondaryView: segundaVista(),
    });

    await assertSucceeds(
      updateDoc(ref, {
        imageUrl: `users/${ALICE}/identifications/duas-2/processed.jpg`,
        secondaryView: {
          ...segundaVista(),
          imageUrl: `users/${ALICE}/identifications/duas-2/processed-2.jpg`,
          thumbnailUrl: `users/${ALICE}/identifications/duas-2/thumbnail-2.webp`,
        },
      }),
    );
  });

  it('NÃO acrescenta `fusion` numa atualização', async () => {
    // O caminho "criar limpo, reescrever depois".
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    const ref = doc(db, 'identifications', 'duas-3');
    await setDoc(ref, {
      ...validDoc(ALICE),
      viewCount: 2,
      secondaryView: segundaVista(),
    });

    await assertFails(
      updateDoc(ref, { fusion: { agreeOnTop1: true } }),
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

  // ---------------------------------------------------------------------------
  // HIGH-1 da auditoria: o cliente não escreve resultado de análise.
  // ---------------------------------------------------------------------------
  // Cada um destes casos é a mesma tentativa por um campo diferente. Um
  // registro forjado contamina as métricas de acurácia, entra na fila de
  // revisão humana como se fosse saída do modelo, e alimenta o dataset de
  // retreinamento com rótulo falso.

  it('NÃO cria com confiança — nem um valor válido', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'forja-1'), {
        ...validDoc(ALICE),
        confidence: 0.99,
      }),
    );
  });

  it('NÃO cria com espécie', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'forja-2'), {
        ...validDoc(ALICE),
        speciesId: 'tityus-serrulatus',
      }),
    );
  });

  it('NÃO cria com versão de modelo', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'forja-3'), {
        ...validDoc(ALICE),
        modelVersion: 'scorpion-v9.9',
      }),
    );
  });

  it('NÃO cria já identificada — status é conclusão de análise', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'forja-4'), {
        ...validDoc(ALICE),
        status: 'identified',
      }),
    );
  });

  it('NÃO cria com revisão humana forjada', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'identifications', 'forja-5'), {
        ...validDoc(ALICE),
        reviewedBy: 'especialista-inventado',
      }),
    );
  });

  it('NÃO acrescenta confiança a um documento que já existe', async () => {
    // O caminho mais sutil: criar limpo e reescrever depois. `changedFields()`
    // fecha isso — ele lista o que a escrita está MUDANDO.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'identifications', 'id-alice-1'), {
        confidence: 0.99,
        speciesId: 'tityus-serrulatus',
      }),
    );
  });

  it('ainda anexa os caminhos das imagens, que são do cliente', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'identifications', 'id-alice-1'), {
        imageUrl: 'users/uid-alice/identifications/id-alice-1/processed.jpg',
        thumbnailUrl: 'users/uid-alice/identifications/id-alice-1/thumbnail.jpg',
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
// users/{uid}/quotas/{dia}  — o contador de uso diário
// =============================================================================
//
// A razão de estes testes existirem: o limite de 60 análises por dia só vale
// enquanto o cliente não puder mexer no contador. Se ele puder zerar, o
// MEDIUM-4 volta por uma porta diferente da que foi fechada.
describe('cota diária', () => {
  it('o dono lê a própria cota', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05')),
    );
  });

  it('NÃO lê a cota de outra pessoa', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDoc(doc(db, 'users', BOB, 'quotas', '2026-10-05')));
  });

  it('o dono NÃO zera a própria cota', async () => {
    // O teste mais importante deste bloco. Quem pode escrever aqui não tem
    // limite de uso nenhum.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05'), { count: 0 }),
    );
  });

  it('o dono NÃO diminui o contador por atualização', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05'), { count: 1 }),
    );
  });

  it('o dono NÃO apaga o documento da cota', async () => {
    // Apagar é equivalente a zerar: na próxima leitura o contador começa do
    // zero porque o documento não existe.
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      deleteDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05')),
    );
  });

  it('nem o admin escreve na cota de alguém', async () => {
    // Quem escreve é o backend, com o Admin SDK, que ignora estas regras.
    // Nenhum caminho de cliente, para nenhum papel.
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05'), { count: 0 }),
    );
  });

  it('quem não está autenticado não lê cota', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(doc(db, 'users', ALICE, 'quotas', '2026-10-05')),
    );
  });
});

// =============================================================================
// auditLogs — fechado para todos, inclusive admin
// =============================================================================
describe('audit log', () => {
  it('o usuário comum NÃO lê o audit log', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDoc(doc(db, 'auditLogs', 'qualquer')));
  });

  it('o ADMIN também NÃO lê o audit log', async () => {
    // Deliberado, e o ponto do bloco.
    //
    // O pior cenário por credencial é uma conta administrativa comprometida —
    // e o audit log é justamente o que registraria essa conta agindo. Deixá-lo
    // alcançável pelo papel que ele audita entregaria ao atacante a capacidade
    // de apagar o próprio rastro.
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertFails(getDoc(doc(db, 'auditLogs', 'qualquer')));
  });

  it('ninguém escreve no audit log pelo cliente', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(
      setDoc(doc(db, 'auditLogs', 'forjado'), {
        action: 'account.deleted',
        actorUid: BOB,
        outcome: 'success',
      }),
    );
  });

  it('o admin NÃO apaga entradas do audit log', async () => {
    // "Não apagar evidências durante um incidente" é regra do plano de
    // resposta. Aqui ela é imposta, não pedida.
    const db = asUser(testEnv, ADMIN, ADMIN_EMAIL).firestore();
    await assertFails(deleteDoc(doc(db, 'auditLogs', 'qualquer')));
  });

  it('o usuário NÃO lista o audit log', async () => {
    const db = asUser(testEnv, ALICE, ALICE_EMAIL).firestore();
    await assertFails(getDocs(collection(db, 'auditLogs')));
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
