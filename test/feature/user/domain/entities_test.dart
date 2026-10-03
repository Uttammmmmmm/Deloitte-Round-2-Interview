import 'package:demoapi/feature/user/domain/entity/paged_users.dart';
import 'package:demoapi/feature/user/domain/entity/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = User(
    id: 1,
    email: 'a@a.com',
    firstName: 'Ada',
    lastName: 'Lovelace',
    avatar: '',
  );

  test('User: fullName and value equality', () {
    expect(user.fullName, 'Ada Lovelace');
    expect(
      user,
      const User(
        id: 1,
        email: 'a@a.com',
        firstName: 'Ada',
        lastName: 'Lovelace',
        avatar: '',
      ),
    );
  });

  test('PagedUsers.hasNext is true until the last page', () {
    expect(
      const PagedUsers(users: [user], page: 1, totalPages: 2).hasNext,
      isTrue,
    );
    expect(
      const PagedUsers(users: [user], page: 2, totalPages: 2).hasNext,
      isFalse,
    );
  });

  test('PagedUsers has value equality', () {
    expect(
      const PagedUsers(users: [user], page: 1, totalPages: 2),
      const PagedUsers(users: [user], page: 1, totalPages: 2),
    );
  });
}
