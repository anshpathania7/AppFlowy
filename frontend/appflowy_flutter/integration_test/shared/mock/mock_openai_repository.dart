import 'dart:async';
import 'dart:convert';

import 'package:appflowy/ai/service/error.dart';
import 'package:appflowy/ai/service/openai_client.dart';
import 'package:appflowy/ai/service/text_completion.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MyMockClient extends Mock implements http.Client {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestType = request.method;
    final requestUri = request.url;

    if (requestType == 'POST' &&
        requestUri == OpenAIRequestType.textCompletion.uri) {
      final responseHeaders = <String, String>{
        'content-type': 'text/event-stream',
      };
      final responseBody = Stream.fromIterable([
        utf8.encode(
          '{ "choices": [{"text": "Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula ", "index": 0, "logprobs": null, "finish_reason": null}]}',
        ),
        utf8.encode('\n'),
        utf8.encode('[DONE]'),
      ]);

      // Return a mocked response with the expected data
      return http.StreamedResponse(responseBody, 200, headers: responseHeaders);
    }

    // Return an error response for any other request
    return http.StreamedResponse(const Stream.empty(), 404);
  }
}

class MockOpenAIRepository extends HttpOpenAIRepository {
  MockOpenAIRepository() : super(apiKey: 'dummyKey', client: MyMockClient());

  @override
  Future<void> getStreamedCompletions({
    required String prompt,
    required Future<void> Function() onStart,
    required Future<void> Function(TextCompletionResponse response) onProcess,
    required Future<void> Function() onEnd,
    required void Function(AIError error) onError,
    String? suffix,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool useAction = false,
  }) async {
    final request = http.Request('POST', OpenAIRequestType.textCompletion.uri);
    final response = await client.send(request);

    String previousSyntax = '';
    if (response.statusCode == 200) {
      await for (final chunk in response.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())) {
        await onStart();
        final data = chunk.trim().split('data: ');
        if (data[0] != '[DONE]') {
          final response = TextCompletionResponse.fromJson(
            json.decode(data[0]),
          );
          if (response.choices.isNotEmpty) {
            final text = response.choices.first.text;
            if (text == previousSyntax && text == '\n') {
              continue;
            }
            await onProcess(response);
            previousSyntax = response.choices.first.text;
          }
        } else {
          await onEnd();
        }
      }
    }
  }
}
