/// Fonte única de todo o texto visível ao usuário.
///
/// Nenhuma tela declara literais. Quando a Fase 2 introduzir localização, esta
/// classe vira a implementação `pt_BR` de uma interface gerada por `intl` e as
/// telas não mudam.
abstract final class AppStrings {
  // -- Genéricos -------------------------------------------------------------
  static const String continueLabel = 'Continuar';
  static const String skip = 'Pular';
  static const String back = 'Voltar';
  static const String cancel = 'Cancelar';
  static const String close = 'Fechar';
  static const String tryAgain = 'Tentar novamente';
  static const String seeAll = 'Ver tudo';
  static const String search = 'Buscar';
  static const String loading = 'Carregando…';
  static const String mockBadge = 'DADOS SIMULADOS';

  // -- Onboarding ------------------------------------------------------------
  static const String onb1Title = 'Identifique';
  static const String onb1Body =
      'Fotografe um escorpião e descubra mais sobre ele. '
      'A captura é o começo de uma análise, não um palpite.';
  static const String onb2Title = 'Conheça';
  static const String onb2Body =
      'Espécie, características morfológicas, distribuição geográfica e '
      'referências científicas reunidas em um só lugar.';
  static const String onb3Title = 'Segurança';
  static const String onb3Body =
      'A identificação é informativa. O sistema pode não reconhecer uma '
      'espécie — e, quando não reconhecer, vai dizer isso claramente.';
  static const String onb3Warning =
      'O resultado não substitui avaliação médica nem orientação '
      'profissional. Em caso de acidente, procure atendimento imediatamente.';

  // -- Autenticação ----------------------------------------------------------
  static const String signIn = 'Entrar';
  static const String signInTitle = 'Bem-vindo de volta';
  static const String signInSubtitle =
      'Acesse sua conta para manter seu histórico de identificações.';
  static const String signUp = 'Criar conta';
  static const String signUpTitle = 'Criar conta';
  static const String signUpSubtitle =
      'Leva menos de um minuto. Seu histórico fica associado a você.';
  static const String fieldName = 'Nome';
  static const String fieldEmail = 'E-mail';
  static const String fieldPassword = 'Senha';
  static const String fieldPasswordConfirm = 'Confirmar senha';
  static const String forgotPassword = 'Esqueci minha senha';
  static const String forgotPasswordTitle = 'Recuperar acesso';
  static const String forgotPasswordBody =
      'Informe o e-mail cadastrado. Enviaremos um link de redefinição.';
  static const String forgotPasswordAction = 'Enviar link';
  static const String noAccount = 'Ainda não tem conta?';
  static const String hasAccount = 'Já tem uma conta?';
  static const String socialDivider = 'ou continue com';
  static const String socialSoon = 'Login social chega na próxima fase.';
  static const String signOut = 'Sair';
  static const String signOutConfirm = 'Encerrar a sessão neste dispositivo?';

  // -- Navegação -------------------------------------------------------------
  static const String navHome = 'Início';
  static const String navHistory = 'Histórico';
  static const String navCatalog = 'Catálogo';
  static const String navProfile = 'Perfil';

  // -- Home ------------------------------------------------------------------
  static const String homeCardTitle = 'Encontrou um escorpião?';
  static const String homeCardBody = 'Fotografe e descubra mais sobre ele.';
  static const String identifyCta = 'Identificar escorpião';
  static const String homeShortcuts = 'Atalhos';
  static const String homeLearn = 'Aprenda';
  static const String photoTipsTitle = 'Como fotografar corretamente';
  static const String photoTipsSubtitle =
      'Quatro cuidados que aumentam muito a chance de acerto.';
  static const String homeRecent = 'Identificações recentes';

  // -- Câmera ----------------------------------------------------------------
  static const String cameraGuide = 'Centralize o escorpião na área indicada.';
  static const String cameraHint = 'Boa luz, fundo limpo e corpo inteiro.';
  static const String cameraGallery = 'Galeria';
  static const String cameraPermissionTitle = 'Acesso à câmera';
  static const String cameraPermissionBody =
      'Precisamos da câmera apenas para capturar a foto que será analisada. '
      'A imagem não sai do aparelho nesta versão.';
  static const String cameraPermissionAction = 'Permitir acesso';
  static const String cameraUnavailableTitle = 'Câmera indisponível';
  static const String cameraUnavailableBody =
      'Não foi possível iniciar a câmera neste dispositivo. Você ainda pode '
      'escolher uma foto da galeria.';
  static const String cameraSimulated = 'Modo simulado';

  // -- Confirmação da foto ---------------------------------------------------
  static const String confirmTitle = 'Foto capturada';
  static const String confirmBody =
      'A imagem está nítida e mostra o corpo inteiro do animal?';
  static const String usePhoto = 'Usar esta foto';
  static const String retakePhoto = 'Tirar outra';

  // -- Análise ---------------------------------------------------------------
  static const String analyzingTitle = 'Analisando';
  static const String analyzingCancel = 'Cancelar análise';
  /// Etapas exibidas durante a análise (brief §18).
  ///
  /// São cinco porque essa é a sequência que o pipeline real da Fase 5 vai
  /// executar de fato: normalizar a imagem, detectar o animal, extrair
  /// características, comparar com o catálogo e montar o resultado. Quando o
  /// modelo assumir, ele passa a reportar o índice da etapa corrente e estes
  /// textos deixam de ser simulados sem que a tela mude.
  static const List<String> analyzingSteps = <String>[
    'Preparando imagem…',
    'Detectando escorpião…',
    'Analisando características…',
    'Comparando espécies…',
    'Preparando resultado…',
  ];

  /// Legenda técnica de cada etapa, exibida abaixo do título.
  ///
  /// Dizer o que o sistema está realmente fazendo dá credibilidade científica —
  /// é o oposto de encenar "IA trabalhando" com efeitos.
  static const List<String> analyzingDetails = <String>[
    'Ajustando enquadramento, brilho e resolução',
    'Localizando o animal dentro da fotografia',
    'Medindo proporções de cauda, pinças e télson',
    'Cruzando com o catálogo de referência',
    'Calculando o nível de confiança',
  ];

  // -- Resultado -------------------------------------------------------------
  static const String resultTitle = 'Resultado';
  static const String resultConfidence = 'Confiança';
  static const String resultRegion = 'Ocorrência';
  static const String resultSummary = 'Resumo';
  static const String resultFullInfo = 'Ver informações completas';
  static const String resultSavedToHistory = 'Salvo no histórico';
  static const String unidentifiedTitle =
      'Não foi possível identificar com segurança';
  static const String unidentifiedBody =
      'A imagem pode estar com baixa qualidade ou não apresentar '
      'características suficientes para uma identificação confiável.';
  static const String unidentifiedWhy = 'O que pode ter acontecido';
  static const String choosePhoto = 'Escolher outra foto';

  // -- Espécie ---------------------------------------------------------------
  static const String speciesIdentification = 'Identificação';
  static const String speciesTraits = 'Características';
  static const String speciesDistribution = 'Distribuição';
  static const String speciesMedical = 'Relevância médica';
  static const String speciesMorphology = 'Morfologia';
  static const String mapPlaceholder = 'Mapa de distribuição — Fase 7';
  static const String medicalDisclaimer =
      'Conteúdo informativo. Não é diagnóstico nem orientação de tratamento. '
      'Em caso de acidente, procure atendimento médico imediatamente.';

  // -- Histórico -------------------------------------------------------------
  static const String historyTitle = 'Histórico';
  static const String historyEmptyTitle = 'Nada por aqui ainda';
  static const String historyEmptyBody =
      'Suas identificações aparecem aqui assim que a primeira análise '
      'terminar.';

  // -- Catálogo --------------------------------------------------------------
  static const String catalogTitle = 'Catálogo';
  static const String catalogSubtitle = 'Espécies de referência';
  static const String catalogSearchHint = 'Nome científico ou popular';
  static const String catalogEmptyTitle = 'Nenhuma espécie encontrada';
  static const String catalogEmptyBody = 'Tente outro termo ou remova os filtros.';

  // -- Perfil e configurações ------------------------------------------------
  static const String profileTitle = 'Perfil';
  static const String profileIdentifications = 'Identificações';
  static const String profileSpecies = 'Espécies vistas';
  static const String settingsTitle = 'Configurações';
  static const String settingsNotifications = 'Notificações';
  static const String settingsAppearance = 'Aparência';
  static const String settingsLanguage = 'Idioma';
  static const String settingsPrivacy = 'Privacidade';
  static const String settingsTerms = 'Termos de uso';
  static const String settingsAbout = 'Sobre o aplicativo';
  static const String aboutTitle = 'Sobre';
  static const String comingSoon = 'Disponível em uma fase futura.';

  /// Versão curta de [comingSoon], para o lado direito de linhas de lista,
  /// onde a frase completa não cabe em telas estreitas.
  static const String soon = 'Em breve';
}
