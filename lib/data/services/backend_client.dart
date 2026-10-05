import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_environment.dart';
import 'failure.dart';

/// Resposta do backend, já decodificada.
@immutable
class BackendResponse {
  const BackendResponse({
    required this.statusCode,
    required this.body,
    this.requestId,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Map<String, Object?> body;

  /// `X-Request-Id`. É o que liga o relato do usuário à linha de log do
  /// servidor sem o log precisar guardar quem ele é.
  final String? requestId;

  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// A mensagem que o servidor quis que o usuário visse.
  ///
  /// O backend já cuida de não vazar detalhe interno aqui (§17 do briefing):
  /// `detail` é uma frase para pessoas, e o traço técnico fica no log dele.
  String? get detail {
    final Object? d = body['detail'];
    return d is String && d.isNotEmpty ? d : null;
  }

  /// O servidor pediu que o usuário digite a senha de novo.
  ///
  /// É como `requires_recent_auth` se comunica: 401 com este cabeçalho
  /// significa "reautentique e tente outra vez", diferente de 401 por sessão
  /// expirada, que significa "entre de novo".
  bool get needsReauth => headers['x-reauth-required'] == 'true';
}

/// Chamadas ao backend próprio.
///
/// # O que este cliente garante
/// - **O token vai em todas as chamadas**, obtido na hora. Um token obtido e
///   guardado expiraria em uma hora e o erro apareceria longe da causa.
/// - **HTTPS**, conferido antes de cada chamada e não só na configuração — ver
///   `AppEnvironmentConfig.isBackendUrlSafe` e o achado C-3 da auditoria de
///   criptografia.
/// - **Tempo limite**, para que uma rede ruim não deixe a interface esperando
///   para sempre.
///
/// # O que ele não faz
/// Não guarda nada em disco, não cacheia resposta, não reenvia pedido
/// automaticamente. Reenviar um `DELETE` seria apagar duas vezes; reenviar uma
/// análise consumiria a cota duas vezes. Quem decide repetir é a tela, com o
/// usuário vendo.
abstract interface class BackendClient {
  /// `GET`, devolvendo o corpo decodificado.
  Future<BackendResponse> get(String path);

  /// `DELETE`.
  Future<BackendResponse> delete(String path);

  /// `POST` com corpo JSON.
  Future<BackendResponse> post(String path, Map<String, Object?> body);
}

/// Como o cliente obtém o ID token do usuário no momento da chamada.
///
/// Uma função, e não uma dependência do `firebase_auth`: assim este arquivo não
/// importa Firebase, e o teste passa uma função que devolve um texto qualquer.
typedef IdTokenProvider = Future<String?> Function({bool forceRefresh});

class HttpBackendClient implements BackendClient {
  // `prefer_initializing_formals` é suprimido nas duas atribuições abaixo.
  //
  // O lint sugere `this._idToken` e `this._timeout` como parâmetros. Seguir a
  // sugestão tornaria os nomes da API pública `_idToken:` e `_timeout:` — um
  // sublinhado na assinatura de quem chama, para poupar duas atribuições. Os
  // campos são privados de propósito, e os parâmetros públicos também.
  HttpBackendClient({
    required IdTokenProvider idToken,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 30),
  })  :
        // ignore: prefer_initializing_formals
        _idToken = idToken,
        // ignore: prefer_initializing_formals
        _timeout = timeout,
        // A barra final é removida para que a concatenação com o caminho não
        // produza `//v1/me`. Alguns servidores tratam isso como outro caminho e
        // respondem 404 — um erro que pareceria do código e é de configuração.
        _baseUrl = (baseUrl ?? AppEnvironmentConfig.backendBaseUrl)
            .replaceAll(RegExp(r'/+$'), '');

  final IdTokenProvider _idToken;
  final String _baseUrl;
  final Duration _timeout;

  @override
  Future<BackendResponse> get(String path) => _enviar('GET', path);

  @override
  Future<BackendResponse> delete(String path) => _enviar('DELETE', path);

  @override
  Future<BackendResponse> post(String path, Map<String, Object?> body) =>
      _enviar('POST', path, body);

  Future<BackendResponse> _enviar(
    String metodo,
    String path, [
    Map<String, Object?>? corpo,
  ]) async {
    // A guarda de TLS é conferida a cada chamada, não uma vez na configuração.
    //
    // Parece redundante e não é: `baseUrl` pode vir pelo construtor, e um teste
    // ou um refatoramento futuro poderiam passar `http://` de um host remoto
    // sem passar por `AppEnvironmentConfig`. A verificação precisa estar no
    // caminho por onde o token de fato sai.
    if (!AppEnvironmentConfig.isUrlSafe(_baseUrl)) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'Configuração de rede inválida. Não foi possível continuar.',
        code: 'insecure_backend_url',
      );
    }

    // No navegador não há `dart:io`.
    //
    // O arquivo compila na web — o Flutter aceita o `import` —, mas `HttpClient`
    // lança `UnsupportedError` na primeira chamada. Sem esta verificação, quem
    // abrisse a pré-visualização web com `BACKEND_URL` definido veria a tela
    // quebrar com um erro de plataforma, e não com uma frase.
    //
    // Dito sem rodeio: as operações de conta **não funcionam no build web**
    // hoje. O aplicativo é mobile, e trazer um cliente HTTP multiplataforma
    // seria uma dependência nova para um alvo que não é o de entrega.
    if (kIsWeb) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'Este recurso está disponível no aplicativo para celular.',
        code: 'backend_unsupported_on_web',
      );
    }

    final String? token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const AppFailure(
        kind: FailureKind.permission,
        message: 'Sua sessão expirou. Entre novamente.',
        code: 'no_id_token',
      );
    }

    final HttpClient http = HttpClient()..connectionTimeout = _timeout;
    try {
      final Uri uri = Uri.parse('$_baseUrl$path');
      final HttpClientRequest pedido = await http
          .openUrl(metodo, uri)
          .timeout(_timeout);

      pedido.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      pedido.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (corpo != null) {
        final List<int> bytes = utf8.encode(jsonEncode(corpo));
        pedido.headers.contentType = ContentType.json;
        pedido.headers.contentLength = bytes.length;
        pedido.add(bytes);
      }

      final HttpClientResponse resposta = await pedido.close().timeout(_timeout);
      final String texto =
          await resposta.transform(utf8.decoder).join().timeout(_timeout);

      return BackendResponse(
        statusCode: resposta.statusCode,
        body: _decodificar(texto),
        requestId: resposta.headers.value('x-request-id'),
        headers: _cabecalhos(resposta),
      );
    } on TimeoutException {
      throw const AppFailure(
        kind: FailureKind.network,
        message: 'O serviço demorou demais para responder. Tente novamente.',
        code: 'backend_timeout',
      );
    } on SocketException {
      throw const AppFailure(
        kind: FailureKind.network,
        message: 'Sem conexão com o serviço. Verifique sua internet.',
        code: 'backend_unreachable',
      );
    } on HandshakeException {
      // Certificado inválido. Pode ser interceptação de tráfego, e por isso a
      // mensagem não sugere "tentar de novo": tentar de novo contra um
      // intermediário é insistir no problema.
      throw const AppFailure(
        kind: FailureKind.network,
        message: 'Não foi possível estabelecer uma conexão segura.',
        code: 'backend_tls',
      );
    } finally {
      http.close(force: true);
    }
  }

  /// Decodifica o corpo, tolerando o que não é JSON.
  ///
  /// Um proxy, um balanceador ou uma página de erro do provedor respondem HTML.
  /// Deixar o `jsonDecode` estourar ali transformaria "o serviço está fora" em
  /// uma exceção de formato, que é um diagnóstico errado.
  static Map<String, Object?> _decodificar(String texto) {
    if (texto.trim().isEmpty) return const <String, Object?>{};
    try {
      final Object? decodificado = jsonDecode(texto);
      if (decodificado is Map<String, Object?>) return decodificado;
      return <String, Object?>{'data': decodificado};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  static Map<String, String> _cabecalhos(HttpClientResponse resposta) {
    final Map<String, String> saida = <String, String>{};
    resposta.headers.forEach((String nome, List<String> valores) {
      if (valores.isNotEmpty) saida[nome.toLowerCase()] = valores.first;
    });
    return saida;
  }
}
