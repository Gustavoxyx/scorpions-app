import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/species.dart';

/// Guarda a consistência entre os dois catálogos de espécies.
///
/// # Por que este arquivo existe
/// O catálogo vive em dois lugares, em duas linguagens:
///
/// - `lib/data/mock/mock_species.dart` — o modo de demonstração, que roda sem
///   rede, sem conta e sem cota;
/// - `firebase/species-data.mjs` — o que os semeadores gravam no Firestore, no
///   emulador e na nuvem.
///
/// Não é duplicação a eliminar: são finalidades diferentes, e o `.mjs` já
/// explica por que ele mesmo existe. O problema é **divergirem em silêncio**.
///
/// O modo de demonstração mostra oito espécies e o catálogo publicado tem
/// cinco. A diferença é deliberada e está registrada em
/// `MockSpecies.demoOnlyIds`, com o motivo.
///
/// # O que este teste protege
/// Que o que pode ser **identificado** — `MockSpecies.identifiable` — é
/// exatamente o catálogo publicado, nos dois sentidos. E que nada mais diverge:
/// um nome científico corrigido em um lado e não no outro, uma família trocada,
/// uma espécie nova que entra só em um dos dois.
///
/// É o mesmo padrão de `contract_shapes_test.dart`, que já pegou um bug real
/// neste projeto: comparar duas representações independentes do mesmo fato.
///
/// # Fragilidade, dita em voz alta
/// Dart não executa JavaScript, então o `.mjs` é lido como **texto** e os
/// campos saem por expressão regular. Se alguém reescrever aquele arquivo com
/// outra formatação, este teste falha sem haver divergência real.
///
/// Isso é aceitável porque a falha é **ruidosa e explicada**: a mensagem diz
/// que não conseguiu extrair, não inventa um resultado. Um teste que, ao não
/// entender o arquivo, concluísse "está tudo igual" seria muito pior.
void main() {
  final File arquivoMjs = File('firebase/species-data.mjs');

  /// Extrai `{id, scientificName, family, genus, specificEpithet}` do `.mjs`.
  List<Map<String, String>> lerCatalogoDoSeed() {
    final String fonte = arquivoMjs.readAsStringSync();

    // Cada espécie começa com `id: '...'`. A partir dele, os campos seguintes
    // são lidos no bloco até o próximo `id:` ou o fim da lista.
    final RegExp blocos = RegExp(
      r"id: '([a-z0-9-]+)',([\s\S]*?)(?=\n  \{|\n\];)",
      multiLine: true,
    );
    RegExp campo(String nome) => RegExp("$nome: '([^']*)'");

    final List<Map<String, String>> achados = <Map<String, String>>[];
    for (final RegExpMatch bloco in blocos.allMatches(fonte)) {
      final String corpo = bloco.group(2)!;
      achados.add(<String, String>{
        'id': bloco.group(1)!,
        for (final String nome in <String>[
          'scientificName',
          'family',
          'genus',
          'specificEpithet',
        ])
          nome: campo(nome).firstMatch(corpo)?.group(1) ?? '',
      });
    }
    return achados;
  }

  test('o arquivo do semeador existe e é legível', () {
    // Sem isto, apagar o `.mjs` faria todas as verificações abaixo passarem
    // sobre uma lista vazia — verde sem ter verificado nada, que é pior que
    // falhar.
    expect(
      arquivoMjs.existsSync(),
      isTrue,
      reason: 'firebase/species-data.mjs não encontrado. Rode o teste da raiz '
          'do projeto.',
    );
  });

  test('a extração do .mjs funcionou', () {
    final List<Map<String, String>> doSeed = lerCatalogoDoSeed();

    expect(
      doSeed,
      isNotEmpty,
      reason: 'nenhuma espécie extraída de species-data.mjs. O formato do '
          'arquivo provavelmente mudou — ajuste a expressão regular deste '
          'teste, não ignore a falha.',
    );

    for (final Map<String, String> e in doSeed) {
      expect(
        e['scientificName'],
        isNotEmpty,
        reason: 'não consegui ler o nome científico de ${e['id']}',
      );
    }
  });

  test('toda espécie do semeador existe no modo de demonstração', () {
    final List<Map<String, String>> doSeed = lerCatalogoDoSeed();
    final Set<String> idsDoMock =
        MockSpecies.all.map((Species s) => s.id).toSet();

    for (final Map<String, String> e in doSeed) {
      expect(
        idsDoMock,
        contains(e['id']),
        reason:
            '${e['id']} está no catálogo semeado mas não no modo de '
            'demonstração. Uma apresentação sem rede não mostraria esta '
            'espécie.',
      );
    }
  });

  test('o que pode ser identificado é exatamente o catálogo publicado', () {
    final Set<String> idsDoSeed =
        lerCatalogoDoSeed().map((Map<String, String> e) => e['id']!).toSet();
    final Set<String> identificaveis =
        MockSpecies.identifiable.map((Species s) => s.id).toSet();

    expect(
      identificaveis,
      idsDoSeed,
      reason: 'a demonstração identificaria uma espécie que a produção não '
          'tem, ou deixaria de fora uma que ela tem.\n'
          '  só na demonstração: ${identificaveis.difference(idsDoSeed)}\n'
          '  só no catálogo publicado: ${idsDoSeed.difference(identificaveis)}',
    );
  });

  test('as espécies só de demonstração existem, e não estão publicadas', () {
    final Set<String> idsDoSeed =
        lerCatalogoDoSeed().map((Map<String, String> e) => e['id']!).toSet();
    final Set<String> idsDoMock =
        MockSpecies.all.map((Species s) => s.id).toSet();

    expect(
      idsDoMock.containsAll(MockSpecies.demoOnlyIds),
      isTrue,
      reason: '`demoOnlyIds` cita uma espécie que não existe no catálogo',
    );
    expect(
      MockSpecies.demoOnlyIds.intersection(idsDoSeed),
      isEmpty,
      reason: 'uma espécie marcada como só de demonstração já foi publicada: '
          'tire-a de `MockSpecies.demoOnlyIds`',
    );
  });

  test('os campos taxonômicos batem para as espécies que existem nos dois', () {
    // O que de fato protege contra o erro silencioso: alguém corrige
    // "Bothriurus bonarensis" para "bonariensis" em um arquivo e esquece o
    // outro. O emulador passaria a testar um conteúdo que a produção não tem.
    final Map<String, Species> porId = <String, Species>{
      for (final Species s in MockSpecies.all) s.id: s,
    };

    for (final Map<String, String> doSeed in lerCatalogoDoSeed()) {
      final Species? noMock = porId[doSeed['id']];
      if (noMock == null) continue; // já coberto pelo teste anterior

      expect(
        doSeed['scientificName'],
        noMock.scientificName,
        reason: 'nome científico divergente em ${doSeed['id']}',
      );
      expect(
        doSeed['family'],
        noMock.family,
        reason: 'família divergente em ${doSeed['id']}',
      );
      expect(
        doSeed['genus'],
        noMock.genus,
        reason: 'gênero divergente em ${doSeed['id']}',
      );
      expect(
        doSeed['specificEpithet'],
        noMock.specificEpithet,
        reason: 'epíteto específico divergente em ${doSeed['id']}',
      );
    }
  });

  test('o id é coerente com o nome científico, nos dois catálogos', () {
    // `Tityus serrulatus` → `tityus-serrulatus`. A convenção é o que liga as
    // duas listas; um id fora dela quebraria a comparação sem ninguém notar.
    String idEsperado(String nomeCientifico) =>
        nomeCientifico.toLowerCase().replaceAll(' ', '-');

    for (final Species s in MockSpecies.all) {
      expect(
        s.id,
        idEsperado(s.scientificName),
        reason: 'no mock, o id de ${s.scientificName} não segue a convenção',
      );
    }

    for (final Map<String, String> e in lerCatalogoDoSeed()) {
      expect(
        e['id'],
        idEsperado(e['scientificName']!),
        reason: 'no seed, o id de ${e['scientificName']} não segue a convenção',
      );
    }
  });
}
