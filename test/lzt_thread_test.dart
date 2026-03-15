import 'dart:io';
import 'package:lzt_api/lzt_api.dart';

void main() async {
  final forum = ForumClient(token: 'test_token');

  final result = (await forum.threadsGet(
    threadId: 123,
  ))['thread'];

  print("id: ${result['thread_id']}, title: ${result['thread_title']}, author: ${result['creator_username']}");
  forum.close();
}