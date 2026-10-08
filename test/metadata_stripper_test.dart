import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/data/services/metadata_stripper.dart';

img.Image _cena() {
  final img.Image im = img.Image(width: 320, height: 240);
  final Random r = Random(11);
  for (int y = 0; y < 240; y++) {
    for (int x = 0; x < 320; x++) {
      final int v = ((0.5 + 0.4 * sin(x / 12)) * 200 + r.nextInt(30))
          .clamp(0, 255)
          .round();
      im.setPixelRgb(x, y, v, 255 - v, (v * 1.3).clamp(0, 255).round());
    }
  }
  return im;
}

Uint8List _comExif() {
  final img.Image im = _cena();
  im.exif.imageIfd['Make'] = 'Aparelho de Teste';
  im.exif.imageIfd['Model'] = 'Modelo XYZ';
  // O que realmente importa esconder: onde a pessoa estava.
  im.exif.gpsIfd['GPSLatitudeRef'] = 'S';
  im.exif.gpsIfd['GPSLongitudeRef'] = 'W';
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

Uint8List _semExif() =>
    Uint8List.fromList(img.encodeJpg(_cena(), quality: 90));

bool _contem(Uint8List bytes, String texto) => _posicao(bytes, texto) >= 0;

int _posicao(Uint8List bytes, String texto) {
  final List<int> alvo = texto.codeUnits;
  for (int i = 0; i + alvo.length <= bytes.length; i++) {
    int j = 0;
    while (j < alvo.length && bytes[i + j] == alvo[j]) {
      j++;
    }
    if (j == alvo.length) return i;
  }
  return -1;
}

/// Um segmento JPEG: FF, marcador, tamanho (que conta a si mesmo), conteúdo.
List<int> _segmento(int marcador, String conteudo) {
  final List<int> dados = conteudo.codeUnits;
  final int tamanho = dados.length + 2;
  return <int>[0xFF, marcador, tamanho >> 8, tamanho & 0xFF, ...dados];
}

/// Insere os segmentos logo depois do início da imagem.
Uint8List _inserirSegmentos(Uint8List jpeg, List<List<int>> segmentos) {
  return Uint8List.fromList(<int>[
    ...jpeg.sublist(0, 2),
    for (final List<int> s in segmentos) ...s,
    ...jpeg.sublist(2),
  ]);
}

/// Um bloco PNG: tamanho, tipo, dados e quatro bytes de verificação. A
/// verificação vai zerada — o removedor não a confere, e o bloco é descartado.
List<int> _blocoPng(String tipo, String conteudo) {
  final List<int> dados = conteudo.codeUnits;
  final ByteData tamanho = ByteData(4)..setUint32(0, dados.length);
  return <int>[
    ...tamanho.buffer.asUint8List(),
    ...tipo.codeUnits,
    ...dados,
    0, 0, 0, 0, //
  ];
}

/// Insere os blocos logo depois do cabeçalho (assinatura de 8 bytes + IHDR).
Uint8List _inserirBlocosPng(Uint8List png, List<List<int>> blocos) {
  const int fimDoIhdr = 8 + 12 + 13;
  return Uint8List.fromList(<int>[
    ...png.sublist(0, fimDoIhdr),
    for (final List<int> b in blocos) ...b,
    ...png.sublist(fimDoIhdr),
  ]);
}

/// Um contêiner WebP montado à mão.
///
/// O removedor trabalha no nível dos blocos e não decodifica a imagem, então o
/// conteúdo do bloco de imagem pode ser qualquer coisa — e tem tamanho ímpar
/// de propósito, para exercitar o byte de alinhamento.
Uint8List _webp({required bool comMetadados}) {
  List<int> bloco(String tipo, List<int> dados) {
    final ByteData tamanho = ByteData(4)
      ..setUint32(0, dados.length, Endian.little);
    return <int>[
      ...tipo.codeUnits,
      ...tamanho.buffer.asUint8List(),
      ...dados,
      if (dados.length.isOdd) 0,
    ];
  }

  // Bits do cabeçalho estendido: 0x10 transparência, 0x08 EXIF, 0x04 XMP.
  final int bits = comMetadados ? 0x10 | 0x08 | 0x04 : 0x10;
  final List<int> corpo = <int>[
    ...bloco('VP8X', <int>[bits, 0, 0, 0, 63, 1, 0, 239, 0, 0]),
    ...bloco('VP8 ', 'dados-da-imagem'.codeUnits),
    if (comMetadados) ...bloco('EXIF', 'II*\u0000 gps-do-webp'.codeUnits),
    if (comMetadados) ...bloco('XMP ', '<x:xmpmeta/>'.codeUnits),
  ];

  final ByteData tamanho = ByteData(4)
    ..setUint32(0, corpo.length + 4, Endian.little);
  return Uint8List.fromList(<int>[
    ...'RIFF'.codeUnits,
    ...tamanho.buffer.asUint8List(),
    ...'WEBP'.codeUnits,
    ...corpo,
  ]);
}

void main() {
  test('o JPEG de partida realmente carrega metadados', () {
    expect(
      MetadataStripper.hasMetadata(_comExif()),
      isTrue,
      reason: 'sem isso o teste seguinte não provaria nada',
    );
  });

  test('remove os metadados', () {
    final Uint8List limpo = MetadataStripper.strip(_comExif())!;
    expect(MetadataStripper.hasMetadata(limpo), isFalse);
  });

  test('o GPS não sobrevive em lugar nenhum do arquivo', () {
    final Uint8List limpo = MetadataStripper.strip(_comExif())!;
    // Procura a assinatura textual do bloco EXIF nos bytes crus.
    const List<int> marcaExif = <int>[0x45, 0x78, 0x69, 0x66]; // "Exif"
    bool contem = false;
    for (int i = 0; i + 3 < limpo.length; i++) {
      if (limpo[i] == marcaExif[0] &&
          limpo[i + 1] == marcaExif[1] &&
          limpo[i + 2] == marcaExif[2] &&
          limpo[i + 3] == marcaExif[3]) {
        contem = true;
        break;
      }
    }
    expect(contem, isFalse);

    final img.Image? relido = img.decodeJpg(limpo);
    expect(relido, isNotNull);
    expect(relido!.exif.gpsIfd.isEmpty, isTrue);
  });

  test('os pixels não são tocados — nenhuma recompressão', () {
    final Uint8List original = _comExif();
    final Uint8List limpo = MetadataStripper.strip(original)!;

    final img.Image a = img.decodeJpg(original)!;
    final img.Image b = img.decodeJpg(limpo)!;

    expect(b.width, a.width);
    expect(b.height, a.height);

    // Igualdade exata: recompressão mudaria estes valores.
    for (final List<int> ponto in <List<int>>[
      <int>[0, 0],
      <int>[160, 120],
      <int>[319, 239],
      <int>[75, 200],
    ]) {
      final img.Pixel pa = a.getPixel(ponto[0], ponto[1]);
      final img.Pixel pb = b.getPixel(ponto[0], ponto[1]);
      expect(<num>[pb.r, pb.g, pb.b], <num>[pa.r, pa.g, pa.b]);
    }
  });

  test('o arquivo limpo é menor', () {
    final Uint8List original = _comExif();
    expect(
      MetadataStripper.strip(original)!.length,
      lessThan(original.length),
    );
  });

  group('quando não dá para garantir, devolve nulo', () {
    // Nulo manda quem chama recomprimir. O que não pode acontecer é devolver
    // os bytes de entrada como se estivessem limpos — era o comportamento
    // anterior, e deixava a localização subir num JPEG fora do padrão.
    test('formato desconhecido', () {
      final Uint8List gif = Uint8List.fromList(
        <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0, 0, 0, 0],
      );
      expect(MetadataStripper.strip(gif), isNull);
      expect(MetadataStripper.hasMetadata(gif), isTrue);
    });

    test('JPEG com estrutura inválida', () {
      final Uint8List lixo =
          Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0x00, 0x99, 0x42]);
      expect(MetadataStripper.strip(lixo), isNull);
    });

    test('JPEG truncado no meio de um segmento', () {
      final Uint8List cortado = Uint8List.sublistView(_comExif(), 0, 40);
      expect(MetadataStripper.strip(cortado), isNull);
    });

    test('JPEG truncado no meio dos dados comprimidos', () {
      final Uint8List completo = _comExif();
      final Uint8List cortado =
          Uint8List.sublistView(completo, 0, completo.length - 200);
      expect(MetadataStripper.strip(cortado), isNull);
    });

    test('PNG truncado', () {
      final Uint8List png = Uint8List.fromList(img.encodePng(_cena()));
      expect(
        MetadataStripper.strip(Uint8List.sublistView(png, 0, png.length - 9)),
        isNull,
      );
    });

    test('WebP cujo tamanho declarado passa do arquivo', () {
      final Uint8List webp = _webp(comMetadados: true);
      expect(
        MetadataStripper.strip(Uint8List.sublistView(webp, 0, webp.length - 5)),
        isNull,
      );
    });
  });

  group('JPEG: lista do que fica, não do que sai', () {
    test('blocos que ninguém listou também saem', () {
      // APP11 é onde vão as credenciais de conteúdo; APP12 é de fabricante.
      // A versão anterior só conhecia EXIF, IPTC e comentário.
      final Uint8List sujo = _inserirSegmentos(_semExif(), <List<int>>[
        _segmento(0xEB, 'JP\u0000credencial de conteudo'),
        _segmento(0xEC, 'Ducky dado de fabricante'),
        _segmento(0xFE, 'comentario com endereco'),
      ]);
      expect(MetadataStripper.hasMetadata(sujo), isTrue);

      final Uint8List limpo = MetadataStripper.strip(sujo)!;

      expect(_contem(limpo, 'credencial'), isFalse);
      expect(_contem(limpo, 'fabricante'), isFalse);
      expect(_contem(limpo, 'endereco'), isFalse);
      expect(limpo, _semExif(), reason: 'sobra exatamente a imagem');
    });

    test('o perfil de cor fica; outro uso do mesmo bloco sai', () {
      final Uint8List sujo = _inserirSegmentos(_semExif(), <List<int>>[
        _segmento(0xE2, 'ICC_PROFILE\u0000perfil-de-cor'),
        _segmento(0xE2, 'MPF\u0000indice de outras imagens'),
      ]);

      final Uint8List limpo = MetadataStripper.strip(sujo)!;

      expect(_contem(limpo, 'perfil-de-cor'), isTrue);
      expect(_contem(limpo, 'indice de outras'), isFalse);
    });

    test('o que vem depois do fim da imagem não é copiado', () {
      // Alguns aparelhos anexam um vídeo curto depois do fim do JPEG. Ele não
      // faz parte da fotografia, pesa megabytes e mostra mais do que a foto.
      final Uint8List base = _semExif();
      final Uint8List comVideo = Uint8List.fromList(<int>[
        ...base,
        ...'ftypmp4 video anexado pelo aparelho'.codeUnits,
      ]);

      final Uint8List limpo = MetadataStripper.strip(comVideo)!;

      expect(limpo, base);
      expect(limpo.sublist(limpo.length - 2), <int>[0xFF, 0xD9]);
    });

    test('a imagem limpa continua abrindo, com os mesmos pixels', () {
      final Uint8List sujo = _inserirSegmentos(_comExif(), <List<int>>[
        _segmento(0xEB, 'qualquer coisa'),
      ]);
      final img.Image antes = img.decodeJpg(sujo)!;
      final img.Image depois = img.decodeJpg(MetadataStripper.strip(sujo)!)!;

      expect(depois.width, antes.width);
      final img.Pixel a = antes.getPixel(160, 120);
      final img.Pixel b = depois.getPixel(160, 120);
      expect(<num>[b.r, b.g, b.b], <num>[a.r, a.g, a.b]);
    });
  });

  group('PNG', () {
    test('texto, EXIF e data saem; a imagem fica idêntica', () {
      final Uint8List limpoDeOrigem =
          Uint8List.fromList(img.encodePng(_cena()));
      final Uint8List sujo = _inserirBlocosPng(limpoDeOrigem, <List<int>>[
        _blocoPng('tEXt', 'Location\u0000-23.55,-46.63'),
        _blocoPng('eXIf', 'II*\u0000 gps escondido'),
        _blocoPng('tIME', '2026-10-07'),
        _blocoPng('prVt', 'bloco privado de um editor'),
      ]);
      expect(MetadataStripper.hasMetadata(sujo), isTrue);

      final Uint8List limpo = MetadataStripper.strip(sujo)!;

      expect(_contem(limpo, '-23.55'), isFalse);
      expect(_contem(limpo, 'gps escondido'), isFalse);
      expect(_contem(limpo, 'bloco privado'), isFalse);
      expect(limpo, limpoDeOrigem, reason: 'sobra exatamente o PNG de origem');
      expect(MetadataStripper.hasMetadata(limpo), isFalse);
    });

    test('o que vem depois do fim declarado não é copiado', () {
      final Uint8List png = Uint8List.fromList(img.encodePng(_cena()));
      final Uint8List comSobra =
          Uint8List.fromList(<int>[...png, ...'dado anexado'.codeUnits]);

      expect(MetadataStripper.strip(comSobra), png);
    });
  });

  group('WebP', () {
    test('EXIF e XMP saem, e o cabeçalho deixa de anunciá-los', () {
      final Uint8List sujo = _webp(comMetadados: true);
      expect(MetadataStripper.hasMetadata(sujo), isTrue);

      final Uint8List limpo = MetadataStripper.strip(sujo)!;

      expect(_contem(limpo, 'EXIF'), isFalse);
      expect(_contem(limpo, 'XMP '), isFalse);
      expect(_contem(limpo, 'gps-do-webp'), isFalse);
      expect(_contem(limpo, 'dados-da-imagem'), isTrue);

      // Dois bits do cabeçalho estendido dizem "há EXIF" e "há XMP".
      final int vp8x = _posicao(limpo, 'VP8X');
      expect(limpo[vp8x + 8] & 0x0C, 0);
      // O bit de transparência, que não tem a ver com metadado, fica.
      expect(limpo[vp8x + 8] & 0x10, 0x10);

      // O tamanho declarado bate com o arquivo que saiu.
      final int declarado = ByteData.sublistView(limpo).getUint32(4, Endian.little);
      expect(declarado + 8, limpo.length);
    });

    test('um WebP já limpo sai igual', () {
      final Uint8List limpoDeOrigem = _webp(comMetadados: false);
      expect(MetadataStripper.strip(limpoDeOrigem), limpoDeOrigem);
      expect(MetadataStripper.hasMetadata(limpoDeOrigem), isFalse);
    });
  });

  group('leitura da etiqueta de orientação', () {
    test('devolve o valor gravado', () {
      for (final int o in <int>[1, 3, 6, 8]) {
        final img.Image im = _cena();
        im.exif.imageIfd.orientation = o;
        final Uint8List bytes =
            Uint8List.fromList(img.encodeJpg(im, quality: 90));
        expect(MetadataStripper.readJpegOrientation(bytes), o);
      }
    });

    test('devolve nulo quando não há EXIF', () {
      final Uint8List bytes =
          Uint8List.fromList(img.encodeJpg(_cena(), quality: 90));
      expect(MetadataStripper.readJpegOrientation(bytes), isNull);
    });

    test('devolve nulo em arquivo que não é JPEG', () {
      expect(
        MetadataStripper.readJpegOrientation(
            Uint8List.fromList(img.encodePng(_cena()))),
        isNull,
      );
    });

    test('não quebra com arquivo truncado', () {
      final img.Image im = _cena();
      im.exif.imageIfd.orientation = 6;
      final Uint8List completo =
          Uint8List.fromList(img.encodeJpg(im, quality: 90));
      for (final int corte in <int>[8, 20, 40, 100]) {
        expect(
          () => MetadataStripper.readJpegOrientation(
              Uint8List.sublistView(completo, 0, corte)),
          returnsNormally,
        );
      }
    });
  });

  test('o decodificador do pacote `image` já entrega os pixels de pé', () {
    // Comportamento de biblioteca, fixado aqui de propósito: o pipeline conta
    // com ele e não chama `bakeOrientation`. Se uma versão futura parar de
    // aplicar a orientação na decodificação, este teste falha e avisa.
    final img.Image im = _cena(); // 320x240
    im.exif.imageIfd.orientation = 6; // 90 graus
    final img.Image decodificada =
        img.decodeJpg(Uint8List.fromList(img.encodeJpg(im, quality: 90)))!;
    expect(decodificada.width, 240);
    expect(decodificada.height, 320);
  });
}
