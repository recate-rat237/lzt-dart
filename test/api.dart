import 'package:test/test.dart';
import 'package:lzt_api/lzt_api.dart';

void main() async {
  group('ForumClient', () {
    late ForumClient client;

    client = ForumClient(token: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzUxMiJ9.eyJzdWIiOjU3MzAyNDgsImlzcyI6Imx6dCIsImlhdCI6MTc3MzU0MzI3NywianRpIjoiOTQ1ODkzIiwic2NvcGUiOiJiYXNpYyByZWFkIHBvc3QgY29udmVyc2F0ZSBwYXltZW50IGludm9pY2UgY2hhdGJveCBtYXJrZXQiLCJleHAiOjE5MzEyMjMyNzd9.SoyIvCX3GZz92Jc7G07eQ68UkFyiINbQ4K4f3EfLVcBnD2t7TfzOWzsQJoOCg05z8l5dVZ6-HZwbAsRO919TbYRd7cS6FGj8fGQC4pTfIOZkT0HAtC8LyWYxXjas9Zc8N9hWNP9Q6LXuFVQ_yhj_z9j8E9Lx-1ORjLBgOS-QPcw');


    client.threadsList().then((threads) {
      print(threads);
    }).catchError((e) {
      print('Error fetching threads: $e');
    });

  });
}
