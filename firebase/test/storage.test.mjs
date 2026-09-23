import { after, before, beforeEach, describe, it } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getDownloadURL, deleteObject } from 'firebase/storage';

import {
  ALICE,
  ALICE_EMAIL,
  BOB,
  BOB_EMAIL,
  TINY_PNG,
  asUser,
  createTestEnv,
} from './helpers.mjs';

let testEnv;

/** Caminho previsto pelo brief §14. */
const alicePath = `users/${ALICE}/identifications/id-1/original.jpg`;
const bobPath = `users/${BOB}/identifications/id-1/original.jpg`;

const imageMeta = { contentType: 'image/jpeg' };

before(async () => {
  testEnv = await createTestEnv();
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearStorage();
});

describe('upload de imagem de identificação', () => {
  it('envia para o próprio caminho', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, alicePath), TINY_PNG, imageMeta),
    );
  });

  it('NÃO envia para o caminho de outra pessoa', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertFails(
      uploadBytes(ref(storage, bobPath), TINY_PNG, imageMeta),
    );
  });

  it('NÃO envia sem estar autenticado', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      uploadBytes(ref(storage, alicePath), TINY_PNG, imageMeta),
    );
  });

  // Brief §19: o tipo de conteúdo é validado. Barra o descuidado; a validação
  // confiável do conteúdo real pertence ao servidor (Fase 4).
  it('NÃO envia arquivo que não é imagem', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertFails(
      uploadBytes(
        ref(storage, `users/${ALICE}/identifications/id-1/original.jpg`),
        Buffer.from('MZ\x90\x00executavel'),
        { contentType: 'application/octet-stream' },
      ),
    );
  });

  it('NÃO envia arquivo acima do limite de 8 MB', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    const tooBig = Buffer.alloc(9 * 1024 * 1024, 1);
    await assertFails(
      uploadBytes(ref(storage, alicePath), tooBig, imageMeta),
    );
  });

  // Brief §19: o caminho não pode virar depósito arbitrário.
  it('NÃO envia com nome de arquivo fora do previsto', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertFails(
      uploadBytes(
        ref(storage, `users/${ALICE}/identifications/id-1/payload.exe`),
        TINY_PNG,
        imageMeta,
      ),
    );
  });

  it('NÃO envia para a raiz do bucket', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertFails(
      uploadBytes(ref(storage, 'original.jpg'), TINY_PNG, imageMeta),
    );
  });

  it('NÃO envia para um caminho inventado', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertFails(
      uploadBytes(ref(storage, 'publico/qualquer.jpg'), TINY_PNG, imageMeta),
    );
  });
});

describe('leitura e remoção', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(
        ref(context.storage(), alicePath),
        TINY_PNG,
        imageMeta,
      );
    });
  });

  it('lê a própria imagem', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertSucceeds(getDownloadURL(ref(storage, alicePath)));
  });

  // As fotografias são dado potencialmente sensível (§15, §36): nunca públicas.
  it('NÃO lê a imagem de outra pessoa', async () => {
    const storage = asUser(testEnv, BOB, BOB_EMAIL).storage();
    await assertFails(getDownloadURL(ref(storage, alicePath)));
  });

  it('quem não está autenticado não lê imagem alguma', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(getDownloadURL(ref(storage, alicePath)));
  });

  it('remove a própria imagem', async () => {
    const storage = asUser(testEnv, ALICE, ALICE_EMAIL).storage();
    await assertSucceeds(deleteObject(ref(storage, alicePath)));
  });

  it('NÃO remove a imagem de outra pessoa', async () => {
    const storage = asUser(testEnv, BOB, BOB_EMAIL).storage();
    await assertFails(deleteObject(ref(storage, alicePath)));
  });
});
