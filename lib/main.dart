import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/film_selector_screen.dart';
import 'package:onlystream/services/ApiService.dart';

//import 'package:flutter_dotenv/flutter_dotenv.dart';

/*
Be careful to not use Future<void> becouse it breaks the stream
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if(!await Apiservice.checkHelth())return;
  //await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

// [Main_Application]
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: Colors.red,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const FilmSelectorScreen(),
    );
  }
}
