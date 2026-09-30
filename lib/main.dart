import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/home_screen.dart';
import 'package:onlystream/services/ApiService.dart';

/// Punto di ingresso principale dell'applicazione OnlyStream. Inizializza i framework grafici e multimediali.
/// Riceve: Nessun parametro.
/// Ritorna:
///   - `void`: Esecuzione asincrona dell'avvio dell'applicazione.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await Apiservice.checkHelth();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Costruisce il widget radice dell'applicazione configurando il tema scuro e la schermata iniziale HomeScreen.
  /// Riceve:
  ///   - `context` (BuildContext): Contesto dell'albero dei widget.
  /// Ritorna:
  ///   - `Widget`: Applicazione MaterialApp configurata.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE50914),
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      ),
      home: const HomeScreen(),
    );
  }
}

