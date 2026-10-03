import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/user/domain/entity/paged_users.dart';
import 'package:demoapi/feature/user/domain/entity/user.dart';
import 'package:demoapi/feature/user/domain/repository/user_repository.dart';
import 'package:demoapi/feature/user/domain/usecase/get_users.dart';
import 'package:demoapi/feature/user/presentation/cubit/user_cubit.dart';
import 'package:demoapi/feature/user/presentation/pages/user_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Possible only because the UI depends on the UserRepository INTERFACE.
class FakeUserRepository implements UserRepository {
  FakeUserRepository({this.failFirstCall = false, this.failPage2Once = false});

  bool failFirstCall;
  bool failPage2Once;

  @override
  Future<PagedUsers> getUsers({required int page}) async {
    if (failFirstCall) {
      failFirstCall = false;
      throw const NetworkFailure('No internet connection.');
    }
    if (page == 2 && failPage2Once) {
      failPage2Once = false;
      throw const NetworkFailure('No internet connection.');
    }
    return PagedUsers(
      page: page,
      totalPages: 2,
      users: List.generate(
        6,
        (i) => User(
          id: (page - 1) * 6 + i,
          email: 'u${(page - 1) * 6 + i}@mail.com',
          firstName: 'First${(page - 1) * 6 + i}',
          lastName: 'Last',
          avatar: '',
        ),
      ),
    );
  }
}

Widget _app(FakeUserRepository repo) => MaterialApp(
  home: BlocProvider(
    create: (_) => UserCubit(GetUsers(repo))..fetchUsers(),
    child: const UserPage(),
  ),
);

void main() {
  testWidgets('shows loader, users, then auto-loads page 2', (tester) async {
    await tester.pumpWidget(_app(FakeUserRepository()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('First0 Last'), findsOneWidget);

    // ListView is lazy: scroll to the last row to prove page 2 was appended.
    await tester.scrollUntilVisible(find.text('First11 Last'), 200);
    expect(find.text('First11 Last'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing); // max reached
  });

  testWidgets('error view with Retry recovers', (tester) async {
    await tester.pumpWidget(_app(FakeUserRepository(failFirstCall: true)));
    await tester.pumpAndSettle();

    expect(find.text('No internet connection.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('First0 Last'), findsOneWidget);
  });

  testWidgets('page 2 fails: list stays, footer offers Retry, retry loads it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeUserRepository(failPage2Once: true)));
    await tester.pumpAndSettle();

    // page 1 is still on screen and the footer shows the retry button
    expect(find.text('First0 Last'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Failed to load. Tap to retry'),
      200,
    );

    await tester.tap(find.text('Failed to load. Tap to retry'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('First11 Last'), 200);
    expect(find.text('First11 Last'), findsOneWidget);
  });
}
