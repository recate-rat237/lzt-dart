import 'dart:io';
import 'package:lzt_api/lzt_api.dart';

void main() async {
  final forum = ForumClient(token: 'your_token');

  final imageBytes = await File('petuh1.jpg').readAsBytes();

  final result = await forum.usersBackgroundUpload(
    userId: "me",
    background: imageBytes,
  );

  print(result);
  forum.close();
}