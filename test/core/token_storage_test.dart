import 'package:demoapi/core/storage/token_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage secure;
  late TokenStorage storage;

  setUp(() {
    secure = MockSecureStorage();
    storage = TokenStorage(secure);
    when(
      () => secure.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => secure.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  test('reads access and refresh tokens from their own keys', () async {
    when(() => secure.read(key: 'access_token')).thenAnswer((_) async => 'a');
    when(() => secure.read(key: 'refresh_token')).thenAnswer((_) async => 'r');

    expect(await storage.readAccess(), 'a');
    expect(await storage.readRefresh(), 'r');
  });

  test('keychain unavailable (PlatformException) = not logged in', () async {
    when(() => secure.read(key: any(named: 'key')))
        .thenThrow(PlatformException(code: '-34018'));

    expect(await storage.readAccess(), isNull);
    expect(await storage.readRefresh(), isNull);
  });

  test('save writes access, and refresh only when given', () async {
    await storage.save(access: 'a');
    verify(() => secure.write(key: 'access_token', value: 'a')).called(1);
    verifyNever(
      () => secure.write(
        key: 'refresh_token',
        value: any(named: 'value'),
      ),
    );

    await storage.save(access: 'a2', refresh: 'r2');
    verify(() => secure.write(key: 'refresh_token', value: 'r2')).called(1);
  });

  test('clear removes both tokens', () async {
    await storage.clear();

    verify(() => secure.delete(key: 'access_token')).called(1);
    verify(() => secure.delete(key: 'refresh_token')).called(1);
  });
}
