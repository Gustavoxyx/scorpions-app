import 'package:flutter/foundation.dart';

/// Um trecho de um documento legal.
@immutable
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

/// Um documento que o usuário pode ler dentro do aplicativo.
@immutable
class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.version,
    required this.sections,
    this.notice,
  });

  final String title;

  /// Identifica **qual texto** a pessoa leu. É o que fica gravado no aceite:
  /// quando o texto muda, a versão muda, e dá para saber quem aceitou o quê.
  ///
  /// Nulo enquanto o documento não foi publicado.
  final String? version;

  /// Aviso exibido no topo — por exemplo, que o texto é preliminar.
  final String? notice;

  final List<LegalSection> sections;

  bool get isPublished => version != null;
}

/// Os documentos legais do aplicativo.
///
/// # O que este arquivo é, e o que não é
/// O aviso de privacidade abaixo **descreve o que o aplicativo faz** com os
/// dados: o que coleta, onde guarda, quem vê. Cada frase corresponde a algo
/// que o código faz, e precisa ser revista quando o código mudar.
///
/// Ele não é parecer jurídico. Não afirma base legal, não nomeia controlador
/// nem encarregado, e não promete conformidade com lei alguma — isso depende de
/// definição da instituição responsável pelo projeto, e está marcado como
/// pendente no próprio texto.
///
/// Os termos de uso não existem ainda, e a tela diz isso em vez de exibir um
/// texto inventado.
abstract final class LegalDocuments {
  /// Versão do aviso em vigor. Mude sempre que o texto mudar.
  static const String privacyVersion = '2026-10-preliminar';

  static const LegalDocument privacy = LegalDocument(
    title: 'Aviso de privacidade',
    version: privacyVersion,
    notice: 'Texto preliminar. A versão definitiva depende de definição da '
        'instituição responsável pelo projeto. Este aviso descreve o que o '
        'aplicativo faz hoje com os seus dados.',
    sections: <LegalSection>[
      LegalSection(
        'O que coletamos',
        'O nome e o e-mail que você informa no cadastro. As fotografias que '
            'você envia para identificar. Medidas tiradas de cada foto no '
            'próprio aparelho — nitidez, luz e resolução —, a data do envio e '
            'a contagem de quantas identificações você fez no dia.\n\n'
            'A senha é entregue ao serviço de autenticação e fica com ele. '
            'O aplicativo não a guarda.',
      ),
      LegalSection(
        'O que não coletamos',
        'Localização, contatos, telefone, nem dados de uso para estatística '
            'ou publicidade.\n\n'
            'A câmera costuma gravar a localização dentro do arquivo da foto. '
            'Essa informação é removida no aparelho, antes do envio.',
      ),
      LegalSection(
        'Para que usamos',
        'Para identificar o escorpião da fotografia e manter o seu histórico '
            'de identificações. As fotografias não são públicas.',
      ),
      LegalSection(
        'Onde ficam',
        'O histórico fica em um banco de dados do Google Firebase hospedado '
            'em São Paulo. A conta — e-mail e senha — é mantida pelo serviço '
            'de autenticação do Google.',
      ),
      LegalSection(
        'Quem pode ver',
        'Você. A equipe responsável pelo projeto, com papel de administração, '
            'pode acessar os registros para manter o serviço e revisar '
            'identificações.',
      ),
      LegalSection(
        'Por quanto tempo',
        'Enquanto a sua conta existir. O prazo de guarda depois de um período '
            'sem uso ainda não foi definido.',
      ),
      LegalSection(
        'O que você pode fazer',
        'Em Perfil › Configurações › Meus dados você pode exportar uma cópia '
            'dos seus dados e excluir a conta com tudo o que pertence a ela.\n\n'
            'As duas operações dependem do serviço online do projeto. Quando '
            'ele não está disponível, a própria tela informa.',
      ),
      LegalSection(
        'Contato',
        'O canal de contato do responsável pelo tratamento dos dados será '
            'informado na versão definitiva deste aviso.',
      ),
    ],
  );

  static const LegalDocument terms = LegalDocument(
    title: 'Termos de uso',
    version: null,
    notice: 'Os termos de uso ainda não foram publicados. Eles dependem de '
        'definição da instituição responsável pelo projeto.',
    sections: <LegalSection>[],
  );
}
