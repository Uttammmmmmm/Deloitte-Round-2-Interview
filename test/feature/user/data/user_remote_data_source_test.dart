import 'package:demoapi/core/network/dio_client.dart';
import 'package:demoapi/feature/user/data/data_source/user_remote_data_source_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

void main() {
  late MockDioClient client;
  late UserRemoteDataSourceImpl dataSource;

  setUp(() {
    client = MockDioClient();
    dataSource = UserRemoteDataSourceImpl(client);
  });

  test('GET /users?page=2 and parses the JSON', () async {
    when(() => client.get('/users', query: any(named: 'query'))).thenAnswer(
      (_) async => {
        'page': 2,
        'per_page': 6,
        'total': 12,
        'total_pages': 2,
        'data': [
          {
            'id': 7,
            'email': 'm@reqres.in',
            'first_name': 'Michael',
            'last_name': 'Lawson',
            'avatar': 'x.jpg',
          },
        ],
      },
    );

    final result = await dataSource.getUsers(page: 2);

    expect(result.page, 2);
    expect(result.data.single.firstName, 'Michael');
    verify(() => client.get('/users', query: {'page': 2})).called(1);
  });
}
