import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/user/domain/entity/paged_users.dart';
import 'package:demoapi/feature/user/domain/entity/user.dart';
import 'package:demoapi/feature/user/domain/usecase/get_users.dart';
import 'package:demoapi/feature/user/presentation/cubit/user_cubit.dart';
import 'package:demoapi/feature/user/presentation/cubit/user_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

class MockGetUsers extends Mock implements GetUsers {}

void main() {
  late MockGetUsers getUsers;

  const user1 = User(
    id: 1,
    email: 'a@a.com',
    firstName: 'A',
    lastName: 'One',
    avatar: '',
  );
  const user2 = User(
    id: 2,
    email: 'b@b.com',
    firstName: 'B',
    lastName: 'Two',
    avatar: '',
  );
  const page1 = PagedUsers(users: [user1], page: 1, totalPages: 2);
  const page2 = PagedUsers(users: [user2], page: 2, totalPages: 2);

  setUp(() => getUsers = MockGetUsers());

  group('fetchUsers', () {
    blocTest<UserCubit, UserState>(
      'emits [Loading, Loaded] on success',
      build: () {
        when(() => getUsers(page: 1)).thenAnswer((_) async => page1);
        return UserCubit(getUsers);
      },
      act: (cubit) => cubit.fetchUsers(),
      expect: () => const [
        UserLoading(),
        UserLoaded(users: [user1], currentPage: 1, totalPages: 2),
      ],
    );

    blocTest<UserCubit, UserState>(
      'emits [Loading, Error] on failure',
      build: () {
        when(() => getUsers(page: 1))
            .thenThrow(const NetworkFailure('No internet connection.'));
        return UserCubit(getUsers);
      },
      act: (cubit) => cubit.fetchUsers(),
      expect: () => const [UserLoading(), UserError('No internet connection.')],
    );
  });

  group('loadMore', () {
    blocTest<UserCubit, UserState>(
      'appends page 2 to page 1',
      build: () {
        when(() => getUsers(page: 2)).thenAnswer((_) async => page2);
        return UserCubit(getUsers);
      },
      seed: () =>
          const UserLoaded(users: [user1], currentPage: 1, totalPages: 2),
      act: (cubit) => cubit.loadMore(),
      expect: () => const [
        UserLoaded(
          users: [user1],
          currentPage: 1,
          totalPages: 2,
          isLoadingMore: true,
        ),
        UserLoaded(users: [user1, user2], currentPage: 2, totalPages: 2),
      ],
    );

    blocTest<UserCubit, UserState>(
      'does nothing when last page reached',
      build: () => UserCubit(getUsers),
      seed: () =>
          const UserLoaded(users: [user1], currentPage: 2, totalPages: 2),
      act: (cubit) => cubit.loadMore(),
      expect: () => const <UserState>[],
      verify: (_) => verifyNever(() => getUsers(page: any(named: 'page'))),
    );

    blocTest<UserCubit, UserState>(
      'keeps the list and flags loadMoreFailed when page 2 fails',
      build: () {
        when(() => getUsers(page: 2))
            .thenThrow(const ServerFailure('Server error.'));
        return UserCubit(getUsers);
      },
      seed: () =>
          const UserLoaded(users: [user1], currentPage: 1, totalPages: 2),
      act: (cubit) => cubit.loadMore(),
      expect: () => const [
        UserLoaded(
          users: [user1],
          currentPage: 1,
          totalPages: 2,
          isLoadingMore: true,
        ),
        UserLoaded(
          users: [user1],
          currentPage: 1,
          totalPages: 2,
          loadMoreFailed: true,
        ),
      ],
    );
  });

  group('hardening', () {
    blocTest<UserCubit, UserState>(
      'a cancelled request is ignored: no error UI',
      build: () {
        when(() => getUsers(page: 1)).thenThrow(const CancelledFailure());
        return UserCubit(getUsers);
      },
      act: (cubit) => cubit.fetchUsers(),
      expect: () => const [UserLoading()],
    );

    blocTest<UserCubit, UserState>(
      'unexpected failures reach Bloc.observer.onError (logging hook)',
      build: () {
        when(() => getUsers(page: 1)).thenThrow(
          UnknownFailure(
            cause: StateError('boom'),
            stackTrace: StackTrace.current,
          ),
        );
        return UserCubit(getUsers);
      },
      act: (cubit) => cubit.fetchUsers(),
      expect: () => const [
        UserLoading(),
        UserError('Something went wrong. Please try again.'),
      ],
      errors: () => [isA<StateError>()],
    );

    blocTest<UserCubit, UserState>(
      'expected failures (offline) are NOT reported as errors',
      build: () {
        when(() => getUsers(page: 1))
            .thenThrow(const NetworkFailure('No internet connection.'));
        return UserCubit(getUsers);
      },
      act: (cubit) => cubit.fetchUsers(),
      expect: () => const [UserLoading(), UserError('No internet connection.')],
      errors: () => <Matcher>[],
    );

    test('a stale response from an earlier fetchUsers() is dropped', () async {
      final slow = Completer<PagedUsers>();
      when(() => getUsers(page: 1)).thenAnswer((_) => slow.future);
      final cubit = UserCubit(getUsers);
      final firstCall = cubit.fetchUsers();

      when(() => getUsers(page: 1)).thenAnswer((_) async => page1);
      await cubit.fetchUsers(); // the user hit Retry; this one wins
      slow.complete(const PagedUsers(users: [user2], page: 1, totalPages: 1));
      await firstCall;

      expect(
        cubit.state,
        const UserLoaded(users: [user1], currentPage: 1, totalPages: 2),
      );
      await cubit.close();
    });

    test(
      'loadMore result is discarded when the list was reloaded meanwhile',
      () async {
        when(() => getUsers(page: 1)).thenAnswer((_) async => page1);
        final cubit = UserCubit(getUsers);
        await cubit.fetchUsers();

        final slowPage2 = Completer<PagedUsers>();
        when(() => getUsers(page: 2)).thenAnswer((_) => slowPage2.future);
        final loading = cubit.loadMore();

        await cubit.fetchUsers(); // refresh while page 2 is in flight
        slowPage2.complete(page2);
        await loading;

        expect(
          cubit.state,
          const UserLoaded(users: [user1], currentPage: 1, totalPages: 2),
          reason: 'page 2 of the OLD list must not be appended to the new one',
        );
        await cubit.close();
      },
    );

    blocTest<UserCubit, UserState>(
      'closing the cubit mid-request does not emit (no StateError)',
      build: () {
        when(() => getUsers(page: 1)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return page1;
        });
        return UserCubit(getUsers);
      },
      act: (cubit) {
        final pending = cubit.fetchUsers();
        cubit.close();
        return pending;
      },
      expect: () => const [UserLoading()],
    );
  });
}
