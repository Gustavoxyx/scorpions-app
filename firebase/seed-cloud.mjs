/**
 * Popula o catálogo de espécies no projeto REAL do Firebase.
 *
 * Uso:
 *   cd firebase
 *   node seed-cloud.mjs            (pergunta e-mail e senha)
 *   node seed-cloud.mjs --dry-run  (mostra o que faria, não escreve nada)
 *
 * -----------------------------------------------------------------------------
 * POR QUE ESTE ARQUIVO EXISTE SEPARADO DE `seed.mjs`
 * -----------------------------------------------------------------------------
 * `seed.mjs` usa `initializeTestEnvironment`, que tem uma propriedade que vale
 * guardar: ela **só conversa com emuladores**. Não existe caminho pelo qual
 * aquele script alcance produção, nem por engano — e é assim que deve ficar.
 *
 * Semear a nuvem é outra operação, com outro risco, e por isso mora em outro
 * arquivo, com as travas correspondentes: confirmação explícita antes de
 * escrever, modo de ensaio, e um alvo fixo no código em vez de herdado de um
 * alias do `firebase-tools` que pode estar apontando para qualquer lugar.
 *
 * -----------------------------------------------------------------------------
 * POR QUE NÃO USA SERVICE ACCOUNT  (briefing §32)
 * -----------------------------------------------------------------------------
 * Um service account do Admin SDK ignora as Security Rules e, se vazar, dá
 * acesso irrestrito ao banco. A regra do projeto é explícita: nenhuma
 * credencial administrativa no repositório, em nenhuma hipótese.
 *
 * Este script entra pela porta da frente — o mesmo SDK cliente do aplicativo,
 * o mesmo login de e-mail e senha — e as regras decidem se ele pode escrever.
 * Isso significa que a conta precisa estar com `role: 'admin'` no documento
 * `users/{uid}` enquanto ele roda. Se não estiver, o Firestore recusa, e a
 * recusa é a prova de que as regras funcionam.
 *
 * A senha é lida do teclado com o eco desligado: não entra no histórico do
 * shell, não vira variável de ambiente, não aparece em lista de processos e
 * não é impressa em lugar nenhum.
 */
import { createInterface } from 'node:readline';
import { stdin, stdout, argv, exit } from 'node:process';

import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import {
  getFirestore,
  doc,
  getDoc,
  writeBatch,
  collection,
  getDocs,
} from 'firebase/firestore';

import { speciesDocuments } from './species-data.mjs';

// -----------------------------------------------------------------------------
// Alvo
// -----------------------------------------------------------------------------
// Escrito aqui, e não lido de `.firebaserc`, de propósito: o alias `default`
// daquele arquivo aponta para o emulador justamente para que um deploy
// distraído não atinja a nuvem. Um script de escrita em produção precisa
// dizer em voz alta onde escreve.
//
// Estes valores não são segredo — são os mesmos de `lib/firebase_options.dart`,
// que vai dentro do aplicativo publicado. Chave de API do Firebase identifica
// o projeto; ela não autoriza nada. Quem autoriza são as Security Rules.
const PROJECT_ID = 'scorpions-tcc-2026';
const CONFIG = {
  apiKey: 'AIzaSyCeUs7TVfXdLcFBt7mGtE0YwNtufG3BSmo',
  authDomain: `${PROJECT_ID}.firebaseapp.com`,
  projectId: PROJECT_ID,
  storageBucket: `${PROJECT_ID}.firebasestorage.app`,
  messagingSenderId: '305720226190',
  appId: '1:305720226190:web:601f0a127114c65312f4df',
};

const DRY_RUN = argv.includes('--dry-run');

// -----------------------------------------------------------------------------
// Entrada
// -----------------------------------------------------------------------------

function ask(question, { hidden = false } = {}) {
  const rl = createInterface({ input: stdin, output: stdout, terminal: true });

  if (!hidden) {
    return new Promise((resolve) =>
      rl.question(question, (answer) => {
        rl.close();
        resolve(answer.trim());
      }),
    );
  }

  // Eco desligado: o terminal não mostra a senha enquanto ela é digitada.
  return new Promise((resolve) => {
    const onData = (char) => {
      if (['\n', '\r', '\u0004'].includes(char.toString())) {
        stdin.removeListener('data', onData);
      } else {
        stdout.write('\u001b[2K\u001b[200D' + question + '*'.repeat(rl.line.length));
      }
    };
    stdin.on('data', onData);
    rl.question(question, (answer) => {
      rl.close();
      stdout.write('\n');
      resolve(answer);
    });
  });
}

function abort(message) {
  console.error(`\n  ${message}\n`);
  exit(1);
}

// -----------------------------------------------------------------------------
// Execução
// -----------------------------------------------------------------------------

const docs = speciesDocuments();

console.log('');
console.log('  Semeadura do catálogo de espécies');
console.log('  ---------------------------------');
console.log(`  Projeto:   ${PROJECT_ID}  (NUVEM, dados reais)`);
console.log(`  Coleção:   species`);
console.log(`  Documentos: ${docs.length}`);
if (DRY_RUN) console.log('  Modo:      ENSAIO — nada será escrito');
console.log('');

if (CONFIG.apiKey.includes('PLACEHOLDER')) {
  abort(
    'A apiKey ainda é um espaço reservado.\n' +
      '  Copie os valores de lib/firebase_options.dart (bloco `web`) para CONFIG.',
  );
}

const app = initializeApp(CONFIG);
const auth = getAuth(app);
const db = getFirestore(app);

const email = await ask('  E-mail da conta administradora: ');
const password = await ask('  Senha: ', { hidden: true });

let user;
try {
  ({ user } = await signInWithEmailAndPassword(auth, email, password));
} catch (error) {
  abort(`Login recusado (${error.code ?? 'erro'}).`);
}

console.log(`\n  Autenticado como ${user.uid}`);

// Confere o papel ANTES de tentar escrever. As regras recusariam de qualquer
// forma, mas falhar no meio de um lote deixaria o catálogo pela metade.
const perfil = await getDoc(doc(db, 'users', user.uid));
const role = perfil.exists() ? perfil.data().role : null;

if (role !== 'admin') {
  await signOut(auth);
  abort(
    `A conta está com role: ${JSON.stringify(role)}.\n` +
      '  Para semear, troque para "admin" no console do Firebase\n' +
      '  (Firestore > users > este documento > role), rode este script,\n' +
      '  e DEVOLVA para "user" logo depois.',
  );
}

const antes = await getDocs(collection(db, 'species'));
console.log(`  Catálogo atual: ${antes.size} documento(s)`);

if (DRY_RUN) {
  console.log('\n  Seriam gravados:');
  for (const { id, data } of docs) {
    console.log(`    species/${id}  —  ${data.scientificName}`);
  }
  console.log('\n  Ensaio concluído. Nada foi escrito.\n');
  await signOut(auth);
  exit(0);
}

const confirmacao = await ask(
  `\n  Escrever ${docs.length} documentos em ${PROJECT_ID}? (digite: sim) `,
);
if (confirmacao.toLowerCase() !== 'sim') {
  await signOut(auth);
  abort('Cancelado. Nada foi escrito.');
}

// Lote único: ou entra tudo, ou não entra nada. Um catálogo pela metade seria
// pior que um catálogo vazio, porque pareceria completo.
const batch = writeBatch(db);
for (const { id, data } of docs) {
  batch.set(doc(db, 'species', id), data);
}

try {
  await batch.commit();
} catch (error) {
  await signOut(auth);
  abort(
    `Escrita recusada (${error.code ?? 'erro'}).\n` +
      '  Se for permission-denied, o role voltou para "user" antes da hora.',
  );
}

const depois = await getDocs(collection(db, 'species'));
console.log(`\n  Gravado. Catálogo agora: ${depois.size} documento(s)`);

await signOut(auth);

console.log('');
console.log('  ATENÇÃO — passo final, não pule:');
console.log('  Devolva a conta para role: "user" no console do Firebase.');
console.log('  Uma conta de uso diário com privilégio de administrador é');
console.log('  exatamente o que as regras existem para evitar.');
console.log('');
exit(0);
