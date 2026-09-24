import 'package:onlystream/models/tv_show_model.dart';

class UserData {
  final int id;
  final String username;
  List<CurrentEpisode> list_current;
  UserData({
    required this.id,
    required this.username,
    required this.list_current,
  });
}
