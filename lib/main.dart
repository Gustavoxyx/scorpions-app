import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'data/services/firebase_bootstrap.dart';

/// Ponto de entrada.
///
/// Mantido deliberadamente mínimo: toda a composição da aplicação vive em
/// `app/app.dart`. Aqui só ficam ajustes que precisam acontecer antes do
/// primeiro frame.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Infraestrutura antes da interface. Em modo simulado esta chamada não faz
  // nada e o aplicativo abre sem tocar em rede.
  await FirebaseBootstrap.ensureInitialized();

  // O aplicativo é desenhado para retrato. Fotografar um escorpião em paisagem
  // muda o enquadramento esperado pelo modelo de visão da Fase 5.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(const ScorpionsApp());
}
