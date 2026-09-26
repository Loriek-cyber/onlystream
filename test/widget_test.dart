import 'package:flutter_test/flutter_test.dart';
import 'package:onlystream/services/ApiService.dart';

void main() {
  test('ApiService checkHelth returns a Future<bool>', () async {
    final result = Apiservice.checkHelth();
    expect(result, isA<Future<bool>>());
  });
}

