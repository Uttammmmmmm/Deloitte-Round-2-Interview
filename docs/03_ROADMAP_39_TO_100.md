# From 39 to 100: upgrading your current `demoapi`

> **How this chapter was verified.** Steps 1–8 were first applied to a copy of your project, running `flutter analyze` after **every** step. They were then applied to your real project, where I **re-audited the result instead of trusting my own projection**. That re-audit measured **86/100** and found concrete gaps, which Step 9 fixes. Final state of your real project: `flutter analyze` (strict mode) → 0 issues, `flutter test` → **74 passed**, ≈**98% line coverage**, `flutter build web` compiles, and the GET/login flows were re-run against the live API. Your original code is backed up in `demoapi_backup_before_100/`, and the state before the hardening round in `demoapi_backup_before_hardening/` (both next to the project folder).
>
> **Honesty note on "100".** Scores are my estimates under the strict rubric from the audit; a real interviewer will weigh things differently. The code base now earns every point except *Live-Coding Speed*: **98/100**. Those last 2 points are about **you**, not the repository: they come from drilling the LITE tier until you can build it in 20 minutes (Step 10).

---

## 1. The score trajectory

Running total after each step (cumulative). Steps 1–7 are estimates; **Step 8's 86 was measured** by a fresh re-audit, and it is *lower* than Step 7 on purpose: adding the auth feature as first written introduced dead code and untested code, which Step 9 then fixes.

| Step | What you do | ≈ time | Score |
|---|---|---|---|
| **Now** | Your code today | n/a | **39** |
| **1** | Fix layering + names (`PagedUsers` into domain, swap the two files, fix typos) | 15 min | **54** |
| **2** | Model → Entity with `toEntity()`, strict parsing | 10 min | **59** |
| **3** | Configure Dio, finish `DioClient`, implement `exceptions.dart` | 15 min | **66** |
| **4** | `failures.dart` + `guard()`, Cubit catches `on Failure` | 10 min | **75** |
| **5** | Equatable states, `fetchUsers`/`loadMore`, widgets, Retry | 25 min | **83** |
| **6** | GetIt, Cubit as factory, `main.dart` | 10 min | **86** |
| **7** | Real tests, delete the red counter test, cleanup | 25 min | **87** |
| **8** | Prove extensibility: Login (POST), secure token storage, auth interceptor | 30 min | **86** (↓ measured) |
| **9** | **Hardening round** from the strict re-audit: mount login, test the interceptor, keep failure causes, cancellation, order-free DI, stale-response guard, strict analyzer, README | 60 min | **98** |
| **10** | Speed drills: LITE tier in 20 minutes, from memory | practice | **100** |

Per-category detail:

| Category | Max | Now | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Architecture | 20 | 8 | **17** | 17 | 17 | 17 | 17 | 18 | 18 | 18 | **20** | 20 |
| BLoC/Cubit | 15 | 6 | 6 | 6 | 6 | 6 | **14** | 14 | 14 | 14 | **15** | 15 |
| API Integration | 15 | 6 | 6 | 6 | **12** | 12 | 12 | 12 | 12 | 12 | **15** | 15 |
| Model/Entity | 10 | 4 | 4 | **9** | 9 | 9 | 9 | 9 | 9 | 9 | **10** | 10 |
| Repository | 10 | 5 | **8** | 8 | 8 | **10** | 10 | 10 | 10 | 10 | 10 | 10 |
| Error Handling | 10 | 1 | 1 | 1 | 1 | **8** | 8 | 8 | 8 | 8 | **10** | 10 |
| Dependency Injection | 5 | 2 | 2 | 2 | 2 | 2 | 2 | **4** | 4 | 4 | **5** | 5 |
| Code Quality | 5 | 2 | **3** | 3 | 3 | 3 | 3 | 3 | **4** | 3 | **5** | 5 |
| SOLID/DRY/KISS | 5 | 2 | **4** | 4 | **5** | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| Live-Coding Speed | 5 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **5** |
| **TOTAL** | **100** | **39** | **54** | **59** | **66** | **75** | **83** | **86** | **87** | **86** | **98** | **100** |

---

## 2. File-by-file migration map

| Your file today | Problem | Becomes |
|---|---|---|
| `core/erros/exceptions.dart` (empty) | typo + empty | `core/errors/exceptions.dart` (Step 3) |
| `core/erros/failuers.dart` (empty) | typo + empty | `core/errors/failures.dart` (Step 4) |
| `core/network/dio_client.dart` | GET-only, unused | 5 verbs + error mapping, **used** by data source (Step 3) |
| `core/constants/api_constants.dart` | base URL concatenated by hand | `baseUrl = '…/api'`, relative paths, timeout (Step 3) |
| `core/di/injection.dart` | `static late`, singleton Cubit, `Dio()` | GetIt, factory Cubit, configured Dio (Step 6) |
| `feature/user/data/data-source/user_remote_data_source_impl.dart` | contains the **interface** | `data_source/user_remote_data_source.dart` (Step 1) |
| `feature/user/data/data-source/user_remote_source_source.dart` | contains the **impl** | `data_source/user_remote_data_source_impl.dart` (Step 1, 3) |
| `feature/user/data/model/user_model.dart` | `extends User`, `?? 0` | standalone model + `toEntity()` (Step 2) |
| `feature/user/data/model/user_response.dart` | domain concept in data layer | **deleted** → `domain/entity/paged_users.dart` (Step 1) |
| `feature/user/data/model/user_response_model.dart` | `extends UserResponse` | `users_response_model.dart` + `toEntity()` (Step 2) |
| `feature/user/data/repositories/user_repository_impl.dart` | pass-through | `data/repository/…` with `guard()` + `toEntity()` (Steps 1, 2, 4) |
| `feature/user/domain/repository/user_repository.dart` | imports **data** | returns `PagedUsers` (Step 1) |
| `feature/user/domain/usecase/get_users.dart` | imports **data** | returns `PagedUsers` (Step 1) |
| `feature/user/presentation/cubit/user_state.dart` | no Equatable, dead fields | Equatable + `copyWith` + `hasReachedMax` (Step 5) |
| `feature/user/presentation/cubit/user_cubit.dart` | `catch (e)`, no `loadMore` | `fetchUsers` + `loadMore` + `on Failure` (Steps 4, 5) |
| `feature/user/presentation/pages/user_page.dart` | TODO, no Retry, no pagination | stateless page + widgets (Step 5) |
| `feature/user/presentation/widget/user_title.dart` (empty) | typo + empty | `widgets/user_tile.dart` (Steps 1, 5) |
| `test/widget_test.dart` | red counter test | real tests (Step 7) |

---

## STEP 1: Fix the layering and the names (39 → 54)

**Goal:** make the dependency rule true: **domain imports nothing from data.** Fix the names an interviewer sees on screen.

**What's wrong (from the audit):** `domain/repository/user_repository.dart:1` and `domain/usecase/get_users.dart:1` import `data/model/user_response.dart`; the two data-source files have each other's contents; folder/file typos.

**Your code today**
```dart
import '../../data/model/user_response.dart';

abstract class UserRepository {
  Future<UserResponse> getUsers({required int page});
}
```
```dart
import '../../domain/entity/user.dart';

class UserResponse {
  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final List<User> users;

  const UserResponse({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.users,
  });
}
```
*(`UserResponse` is "a page of users": a business concept sitting in `data/`.)*

**Do this**

1. Rename folders/files (run from the project root; these exact commands were tested):

```bash
cd lib
mv core/erros core/errors
mv core/errors/failuers.dart core/errors/failures.dart
mv feature/user/data/data-source feature/user/data/data_source
# the two data-source files contain each other's class: swap them
mv feature/user/data/data_source/user_remote_data_source_impl.dart feature/user/data/data_source/_tmp_interface.dart
mv feature/user/data/data_source/user_remote_source_source.dart   feature/user/data/data_source/user_remote_data_source_impl.dart
mv feature/user/data/data_source/_tmp_interface.dart              feature/user/data/data_source/user_remote_data_source.dart
mv feature/user/data/repositories feature/user/data/repository
mv feature/user/presentation/widget feature/user/presentation/widgets
mv feature/user/presentation/widgets/user_title.dart feature/user/presentation/widgets/user_tile.dart
rm feature/user/data/model/user_response.dart
```

2. Create the entity **in domain**: `domain/entity/paged_users.dart`
```dart
import 'package:equatable/equatable.dart';

import 'user.dart';

class PagedUsers extends Equatable {
  const PagedUsers({
    required this.users,
    required this.page,
    required this.totalPages,
  });

  final List<User> users;
  final int page;
  final int totalPages;

  bool get hasNext => page < totalPages;

  @override
  List<Object?> get props => [users, page, totalPages];
}
```
3. Point the domain at it: `domain/repository/user_repository.dart`
```dart
import '../entity/paged_users.dart';

abstract interface class UserRepository {
  Future<PagedUsers> getUsers({required int page});
}
```
and `domain/usecase/get_users.dart`
```dart
import '../entity/paged_users.dart';
import '../repository/user_repository.dart';

class GetUsers {
  const GetUsers(this._repository);

  final UserRepository _repository;

  Future<PagedUsers> call({required int page}) =>
      _repository.getUsers(page: page);
}
```
4. Make `domain/entity/user.dart` the `Equatable` version from the Guide (§4B).
5. Fix the imports that broke: in `user_remote_data_source_impl.dart` import `user_remote_data_source.dart`; in `user_repository_impl.dart` import `../../domain/entity/paged_users.dart` and `../data_source/user_remote_data_source.dart`, return `Future<PagedUsers>`; in `injection.dart` use `data_source/` and `repository/`.
6. **Temporary bridge** so everything compiles before Step 2: make the response model extend the *domain* entity (data → domain is the legal direction; it is replaced in Step 2):
```dart
import '../../domain/entity/paged_users.dart';
import 'user_model.dart';

class UserResponseModel extends PagedUsers {
  const UserResponseModel({
    required super.page,
    required super.totalPages,
    required super.users,
  });

  factory UserResponseModel.fromJson(Map<String, dynamic> json) { /* unchanged */ }
}
```

**Verify**
```bash
flutter analyze                     # 0 issues
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain   # prints NOTHING
```
**Score → 54.** *(Architecture 8→17, Repository 5→8, SOLID 2→4, Quality 2→3.)*
**Say:** *"The domain defines the contract and the data layer adapts to it, so imports point inward."*

---

## STEP 2: Model → Entity with `toEntity()` (54 → 59)

**Goal:** models parse JSON, entities are business. Stop inventing data with `?? 0`.

**Your code today**
```dart
import '../../domain/entity/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.email,
    required super.firstName,
    required super.lastName,
    required super.avatar,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      email: json['email'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      avatar: json['avatar'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'avatar': avatar,
    };
  }
}
```

**Do this:** replace both models; delete `user_response_model.dart`; the data-source interface now returns `UsersResponseModel`; the repository calls `.toEntity()`.

`data/model/user_model.dart`
```dart
import '../../domain/entity/user.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.avatar,
  });

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String avatar;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as int,
    email: json['email'] as String,
    firstName: json['first_name'] as String,
    lastName: json['last_name'] as String,
    avatar: json['avatar'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'avatar': avatar,
  };

  User toEntity() => User(
    id: id,
    email: email,
    firstName: firstName,
    lastName: lastName,
    avatar: avatar,
  );
}
```
`data/model/users_response_model.dart`
```dart
import '../../domain/entity/paged_users.dart';
import 'user_model.dart';

class UsersResponseModel {
  const UsersResponseModel({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.data,
  });

  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final List<UserModel> data;

  factory UsersResponseModel.fromJson(Map<String, dynamic> json) =>
      UsersResponseModel(
        page: json['page'] as int,
        perPage: json['per_page'] as int,
        total: json['total'] as int,
        totalPages: json['total_pages'] as int,
        data: (json['data'] as List)
            .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  PagedUsers toEntity() => PagedUsers(
    users: data.map((m) => m.toEntity()).toList(),
    page: page,
    totalPages: totalPages,
  );
}
```
`data/data_source/user_remote_data_source.dart`
```dart
import '../model/users_response_model.dart';

abstract interface class UserRemoteDataSource {
  Future<UsersResponseModel> getUsers({required int page});
}
```
In `user_repository_impl.dart`:
```dart
final model = await remoteDataSource.getUsers(page: page);
return model.toEntity();
```

**Why strict casts:** `json['id'] as int` fails loudly on a bad contract (Step 4 turns that `TypeError` into a `ParsingFailure`), while `?? 0` would render a blank user with id 0.

**Verify:** `flutter analyze`. **Score → 59** *(Model/Entity 4→9).*
**Say:** *"Model mirrors the API, entity mirrors the business, `toEntity()` is the anti-corruption boundary."*

---

## STEP 3: Configure Dio, finish `DioClient`, implement exceptions (59 → 66)

**Goal:** one configured Dio; every future endpoint is 2–3 lines; no `DioException` above the data layer.

**Your code today**
```dart
import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../model/user_response_model.dart';
import 'user_remote_data_source_impl.dart';

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  final Dio dio;

  UserRemoteDataSourceImpl(this.dio);

  @override
  Future<UserResponseModel> getUsers({required int page}) async {
    try {
      final response = await dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.users}',
        queryParameters: {'page': page},
      );

      return UserResponseModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Something went wrong');
    }
  }
}
```
```dart
import 'package:dio/dio.dart';

class DioClient {
  final Dio dio;

  DioClient(this.dio);

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return dio.get(path, queryParameters: queryParameters);
  }
}
```
*(`Dio()` unconfigured; URL concatenated by hand; the error becomes a bare `Exception`; `DioClient` is GET-only and unused.)*

**Do this**

1. Replace `core/constants/api_constants.dart`, add `core/errors/exceptions.dart`, replace `core/network/dio_client.dart` with the versions in **Guide §4B** (they are the same files shown there).
2. Replace the data-source implementation: it now takes a `DioClient` and uses a **relative** path; no `try/catch` at all:
```dart
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../model/users_response_model.dart';
import 'user_remote_data_source.dart';

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  const UserRemoteDataSourceImpl(this._client);

  final DioClient _client;

  @override
  Future<UsersResponseModel> getUsers({required int page}) async {
    final json = await _client.get(ApiConstants.users, query: {'page': page});
    return UsersResponseModel.fromJson(json as Map<String, dynamic>);
  }
}
```
3. Configure Dio and use the client in `injection.dart` (GetIt comes in Step 6):
```dart
dio = Dio(
  BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: ApiConstants.timeout,
    receiveTimeout: ApiConstants.timeout,
    headers: {'Accept': 'application/json'},
  ),
);
dioClient = DioClient(dio);
userRemoteDataSource = UserRemoteDataSourceImpl(dioClient);
```

**Verify:** `flutter analyze`. **Score → 66** *(API 6→12, SOLID 4→5)*. Until Step 4 the Cubit still prints a raw exception: that is expected.
**Say:** *"`DioClient` is the only code that knows Dio's error types; swap `dio` for `http` and only this file changes."*

---

## STEP 4: Failures and `guard()` (66 → 75)

**Goal:** typed errors end to end: `DioException → AppException → Failure → Cubit → Error state`.

**Do this**

1. Add `core/errors/failures.dart` (Guide §4B): sealed `Failure` family + `guard()`.
```dart
import 'package:equatable/equatable.dart';

import 'exceptions.dart';

/// What the domain / Cubit understands. Always carries a user-safe message.
sealed class Failure extends Equatable implements Exception {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [message, statusCode];
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message);
}

/// 422 / client-side validation: show the message next to the form.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class ParsingFailure extends Failure {
  const ParsingFailure() : super('Unexpected data received from server.');
}

class UnknownFailure extends Failure {
  const UnknownFailure() : super('Something went wrong. Please try again.');
}

/// Repositories wrap every data-source call in this: Exception -> Failure, once.
Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ServerException catch (e) {
    throw switch (e.statusCode) {
      401 || 403 => UnauthorizedFailure(e.message),
      422 => ValidationFailure(e.message),
      _ => ServerFailure(e.message, statusCode: e.statusCode),
    };
  } on NetworkException catch (e) {
    throw NetworkFailure(e.message);
  } on ParsingException {
    throw const ParsingFailure(); // body is not valid JSON
  } on TypeError {
    throw const ParsingFailure(); // wrong JSON shape: null / wrong type
  } on FormatException {
    throw const ParsingFailure();
  } catch (_) {
    throw const UnknownFailure();
  }
}
```
2. The repository becomes three lines, `guard()` does the mapping:
```dart
import '../../../../core/errors/failures.dart';
import '../../domain/entity/paged_users.dart';
import '../../domain/repository/user_repository.dart';
import '../data_source/user_remote_data_source.dart';

class UserRepositoryImpl implements UserRepository {
  const UserRepositoryImpl(this._remote);

  final UserRemoteDataSource _remote;

  @override
  Future<PagedUsers> getUsers({required int page}) =>
      guard(() async => (await _remote.getUsers(page: page)).toEntity());
}
```
3. Your Cubit's catch changes from the catch-all to the typed one:
```dart
// before
} catch (e) {
  emit(UserError(e.toString()));   // "Exception: Something went wrong"
// after
} on Failure catch (failure) {
  emit(UserError(failure.message)); // "No internet connection."
```

**Verify:** `flutter analyze`; run the app in airplane mode: you should see **"No internet connection."**, not an exception string. **Score → 75** *(Error handling 1→8, Repository 8→10).*
**Say:** *"Exceptions are for the data layer; failures are what the rest of the app understands. `guard()` converts once, so repositories stay three lines."*

---

## STEP 5: Cubit, states, pagination and UI (75 → 83)

**Goal:** finish what the half-built state promised: append pages, loader in the footer, retry, no duplicate calls.

**Your code today**
```dart
import '../../domain/entity/user.dart';

sealed class UserState {
  const UserState();
}

class UserInitial extends UserState {
  const UserInitial();
}

class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  final List<User> users;
  final int totalPages;
  final int currentPages;
  final bool isLoadingMore;

  const UserLoaded({
    required this.currentPages,
    required this.totalPages,
    required this.users,
    this.isLoadingMore = false,
  });
}

class UserError extends UserState {
  final String message;
  const UserError(this.message);
}
```
```dart
import 'package:demoapi/feature/user/domain/usecase/get_users.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  final GetUsers getUsers;

  UserCubit(this.getUsers) : super(const UserInitial());

  Future<void> fetchUsers({int page = 1}) async {
    emit(const UserLoading());
    try {
      final response = await getUsers(page: page);
      emit(
        UserLoaded(
          users: response.users,
          currentPages: response.page,
          totalPages: response.totalPages,
        ),
      );
    } catch (e) {
      emit(UserError(e.toString()));
    }
  }
}
```
*(`isLoadingMore` is never set; `fetchUsers(page)` replaces the list; `currentPages`; no equality.)*

**Do this:** replace these files with the versions in **Guide §4B** (all verified; the Cubit is shown below), and create the three widgets:

- `cubit/user_state.dart`: `Equatable`, `copyWith`, `hasReachedMax`, `loadMoreFailed`, `currentPage` (singular).
- `cubit/user_cubit.dart`: `fetchUsers()`, `loadMore()`, `on Failure`, `isClosed`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/usecase/get_users.dart';
import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  UserCubit(this._getUsers) : super(const UserInitial());

  final GetUsers _getUsers;

  /// First page (also used by the Retry button).
  Future<void> fetchUsers() async {
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1);
      if (isClosed) return;
      emit(
        UserLoaded(
          users: result.users,
          currentPage: result.page,
          totalPages: result.totalPages,
        ),
      );
    } on Failure catch (failure) {
      if (isClosed) return;
      emit(UserError(failure.message));
    }
  }

  /// Next page, appended to the current list. Safe to call many times.
  Future<void> loadMore() async {
    final current = state;
    if (current is! UserLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }

    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final result = await _getUsers(page: current.currentPage + 1);
      if (isClosed) return;
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          currentPage: result.page,
          totalPages: result.totalPages,
          isLoadingMore: false,
        ),
      );
    } on Failure {
      if (isClosed) return;
      emit(current.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }
}
```
- `widgets/user_tile.dart`, `widgets/error_view.dart` (Retry), `widgets/load_more_footer.dart`
- `pages/user_page.dart`: stateless, `switch` over the sealed state. **Remove the `initState` + TODO**: the fetch moves to `BlocProvider` (`..fetchUsers()`), so in `main.dart`: `create: (_) => Injection.userCubit..fetchUsers()` (final form in Step 6).

**Verify:** `flutter analyze`; run: page 1 appears, scrolling to the end shows a spinner, then page 2 is appended; with no internet a Retry button appears. **Score → 83** *(Cubit 6→14).*
**Say:** *"`loadMore` ignores calls when not loaded, already loading, or on the last page; if page 2 fails the list stays and the footer offers Retry."*

---

## STEP 6: Dependency injection (83 → 86)

**Goal:** no `static late`; a Cubit **factory** (a singleton Cubit is closed by `BlocProvider` after the first visit).

**Your code today**
```dart
import 'package:dio/dio.dart';

import '../../feature/user/data/data-source/user_remote_data_source_impl.dart';
import '../../feature/user/data/data-source/user_remote_source_source.dart';
import '../../feature/user/data/repositories/user_repository_impl.dart';
import '../../feature/user/domain/repository/user_repository.dart';
import '../../feature/user/domain/usecase/get_users.dart';
import '../../feature/user/presentation/cubit/user_cubit.dart';

class Injection {
  static late Dio dio;

  static late UserRemoteDataSource userRemoteDataSource;
  static late UserRepository userRepository;
  static late GetUsers getUsers;
  static late UserCubit userCubit;

  static void init() {
    dio = Dio();

    userRemoteDataSource = UserRemoteDataSourceImpl(dio);

    userRepository = UserRepositoryImpl(userRemoteDataSource);

    getUsers = GetUsers(userRepository);

    userCubit = UserCubit(getUsers);
  }
}
```
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'feature/user/presentation/pages/user_page.dart';

void main() {
  Injection.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BlocProvider(
        create: (_) => Injection.userCubit,
        child: const UserPage(),
      ),
    );
  }
}
```

**Do this:** add `core/network/safe_log_interceptor.dart` (Guide §11), then replace both files:
```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../feature/user/data/data_source/user_remote_data_source.dart';
import '../../feature/user/data/data_source/user_remote_data_source_impl.dart';
import '../../feature/user/data/repository/user_repository_impl.dart';
import '../../feature/user/domain/repository/user_repository.dart';
import '../../feature/user/domain/usecase/get_users.dart';
import '../../feature/user/presentation/cubit/user_cubit.dart';
import '../constants/api_constants.dart';
import '../network/dio_client.dart';
import '../network/safe_log_interceptor.dart';

final sl = GetIt.instance;

void initDependencies() {
  sl
    // core
    ..registerLazySingleton<Dio>(_createDio)
    ..registerLazySingleton(() => DioClient(sl()))
    // user feature (bottom -> top)
    ..registerLazySingleton<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(sl()),
    )
    ..registerLazySingleton<UserRepository>(() => UserRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetUsers(sl()))
    ..registerFactory(() => UserCubit(sl())); // factory: new Cubit per screen
}

Dio _createDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.timeout,
      receiveTimeout: ApiConstants.timeout,
      headers: {'Accept': 'application/json'},
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(SafeLogInterceptor()); // never in release
  }
  return dio;
}
```
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'feature/user/presentation/cubit/user_cubit.dart';
import 'feature/user/presentation/pages/user_page.dart';

void main() {
  initDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: BlocProvider(
      create: (_) => sl<UserCubit>()..fetchUsers(),
      child: const UserPage(),
    ),
  );
}
```
(Prefer no GetIt in the interview? Use the **manual composition root** shown in Guide §4C; same wiring, zero packages.)

**Verify:** `flutter analyze`; navigate away from the page and back: still works. **Score → 86** *(DI 2→4, Architecture +1).*

---

## STEP 7: Real tests and cleanup (86 → 87)

**Goal:** `flutter test` green with tests that mean something; zero dead code.

**Your test today** (the Flutter template; it **fails**: `LateInitializationError: Field 'userCubit' has not been initialized`)
```dart
// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demoapi/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
```

**Do this**
```bash
flutter pub add --dev bloc_test mocktail
rm test/widget_test.dart
```
Add the five test files from **Guide §17**: `user_cubit_test.dart`, `user_repository_impl_test.dart`, `user_remote_data_source_test.dart`, `dio_client_test.dart`, `user_page_test.dart`.

**Cleanup checklist** (each command prints nothing when you pass):
```bash
find lib -name '*.dart' -size 0                                                  # no empty files
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain  # domain is pure
grep -rnE "package:dio|/data/" lib/feature/*/presentation                         # UI never sees Dio/data
flutter analyze && flutter test                                                   # green
```
Also: remove any unused dependency from `pubspec.yaml`, resolve every `TODO`, pick **one** import style (package imports or relative; be consistent).

**Score → 87** *(Quality 3→4).*

---

## STEP 8: Prove it generalises: POST, secure tokens, interceptor (87 → 86)

**Goal:** show the architecture is a *pattern*, not a one-off: a second feature touches **no** user-feature code.

1. Copy `feature/auth/**` (Guide §9): request/response models, `AuthRemoteDataSource`, `AuthRepositoryImpl`, `Login` use case, `LoginCubit`, `LoginPage`.
2. Add `core/storage/token_storage.dart` (Guide §12) and `flutter pub add flutter_secure_storage`.
3. Add `core/network/auth_interceptor.dart` (Guide §13): Bearer header + refresh-on-401, with the four pitfalls handled.
4. Register it (first version: an `initAuthDependencies()` call in `main()` that also attached the interceptor. **Step 9 replaces this** with an order-free design).
5. Add `test/feature/auth/login_cubit_test.dart` (Guide §17).

**Verify:** log in with `eve.holt@reqres.in` / `cityslicka` → token saved; missing password → snackbar **"Missing password"** (the server's own message, delivered by `DioClient`).
**Score → 86 (↓1, measured).** Adding a feature isn't free. As first written, the login page was **never mounted** (and navigated to a route that doesn't exist), the interceptor and token storage had **no tests**, and the interceptor was attached to Dio imperatively after creation. A strict re-audit counts all of that against you. Step 9 fixes exactly that.
**Say:** *"A new feature is new folders plus one DI call; nothing in the user feature changed. Auth lives in an interceptor, so no repository ever touches a token."*

---

## STEP 9: Hardening round: what a strict re-audit found (86 → 98)

I re-audited the code **as it stood** and verified each suspicion with a command instead of assuming:

| # | Finding (evidence) | Fix |
|---|---|---|
| 1 | `LoginPage` is unreachable: `grep -rn LoginPage lib` finds only its own file, and on success it calls `pushReplacementNamed('/users')`, a route that doesn't exist | `main.dart` mounts `/` and `/login` routes; the users page gets a login icon; success shows a snackbar and **pops**; widget test |
| 2 | `AuthInterceptor`, `TokenStorage`, `AuthRepositoryImpl`, `LoginPage` have **no tests** (`grep` in `test/` → none) | Tests against a **fake HTTP layer**: Bearer header, 401 → refresh → retry, parallel 401s share one refresh, failed refresh clears storage, no refresh token, retry still 401 (no loop), non-401 passthrough; plus storage / repository / page tests |
| 3 | `UserModel.toJson` unused (YAGNI); `DioClient.put/patch/delete` never exercised | `toJson` deleted; all five verbs now tested |
| 4 | `guard()`'s `catch (_)` **throws the original error away**: no way to log it | `Failure` carries `cause` + `stackTrace`; `FailureReporting` mixin forwards them to `Bloc.observer.onError`; `AppBlocObserver` is the single sink (Crashlytics/Sentry hook); the user still only sees a safe message |
| 5 | No cancellation; a cancelled request would show as a *network error* | `CancelToken` on every verb → `CancelledException` → `CancelledFailure`, ignored by Cubits |
| 6 | The interceptor is attached **imperatively** after Dio is created, so it only works if `initAuthDependencies()` runs after `initDependencies()` | `createDio()` is the one place Dio is built (options + `AuthInterceptor` + debug logger); `registerAuthFeature(sl)` registers only the feature's classes; registrations are lazy, so order never matters; DI-graph test |
| 7 | `loadMore` can write a **stale** result back if the list was reloaded while it was in flight | `_generation` counter in `UserCubit`: older responses are dropped; two `Completer` tests prove it |
| 8 | Static analysis is "default", docs are the Flutter template | `strict-casts`, `strict-inference`, `strict-raw-types` + 6 extra lints, 0 issues; a real `README.md`; tests for entities, failures, safe logger |

**The final code for the files that changed**

`core/errors/failures.dart`: failures keep their technical cause
```dart
import 'package:equatable/equatable.dart';

import 'exceptions.dart';

/// What the domain / Cubit understands. [message] is always user-safe.
sealed class Failure extends Equatable implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  final String message;

  /// Technical reason. NEVER shown to users; forwarded to `Bloc.observer.onError`
  /// (see `reportFailure`) so unexpected problems reach your logger/crash tool.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [message, statusCode];
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message);
}

/// 422 / client-side validation: show the message next to the form.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// The request was cancelled on purpose: callers ignore it, no error UI.
class CancelledFailure extends Failure {
  const CancelledFailure() : super('Request cancelled.');
}

class ParsingFailure extends Failure {
  const ParsingFailure({super.cause, super.stackTrace})
    : super('Unexpected data received from server.');
}

class UnknownFailure extends Failure {
  const UnknownFailure({super.cause, super.stackTrace})
    : super('Something went wrong. Please try again.');
}

/// Repositories wrap every data-source call in this: Exception -> Failure, once.
/// Technical causes are kept on the Failure, never swallowed.
Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ServerException catch (e) {
    throw switch (e.statusCode) {
      401 || 403 => UnauthorizedFailure(e.message),
      422 => ValidationFailure(e.message),
      _ => ServerFailure(e.message, statusCode: e.statusCode),
    };
  } on NetworkException catch (e) {
    throw NetworkFailure(e.message);
  } on CancelledException {
    throw const CancelledFailure();
  } on ParsingException catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s); // body is not valid JSON
  } on TypeError catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s); // wrong shape: null / type
  } on FormatException catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s);
  } catch (e, s) {
    throw UnknownFailure(cause: e, stackTrace: s);
  }
}
```
`core/errors/report_failure.dart`: the logging hook
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import 'failures.dart';

mixin FailureReporting<S> on BlocBase<S> {
  /// Forwards the hidden technical cause of a [Failure] (parsing/unknown) to
  /// `Bloc.observer.onError`: one place to plug Crashlytics/Sentry.
  /// Expected failures (offline, 401, 422...) have no cause and are not reported.
  void reportFailure(Failure failure) {
    final cause = failure.cause;
    if (cause != null) addError(cause, failure.stackTrace);
  }
}
```
`feature/user/presentation/cubit/user_cubit.dart`: generation counter + reporting + cancel
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/report_failure.dart';
import '../../domain/usecase/get_users.dart';
import 'user_state.dart';

class UserCubit extends Cubit<UserState> with FailureReporting<UserState> {
  UserCubit(this._getUsers) : super(const UserInitial());

  final GetUsers _getUsers;

  /// Bumped by every fresh load. A response that belongs to an older
  /// generation (user hit Retry, or refreshed meanwhile) is dropped.
  int _generation = 0;

  /// First page (also used by the Retry button).
  Future<void> fetchUsers() async {
    final generation = ++_generation;
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1);
      if (isClosed || generation != _generation) return;
      emit(
        UserLoaded(
          users: result.users,
          currentPage: result.page,
          totalPages: result.totalPages,
        ),
      );
    } on CancelledFailure {
      return; // superseded on purpose: no error UI
    } on Failure catch (failure) {
      reportFailure(failure);
      if (isClosed || generation != _generation) return;
      emit(UserError(failure.message));
    }
  }

  /// Next page, appended to the current list. Safe to call many times.
  Future<void> loadMore() async {
    final current = state;
    if (current is! UserLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }

    final generation = _generation;
    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final result = await _getUsers(page: current.currentPage + 1);
      if (isClosed || generation != _generation) return; // list was reloaded
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          currentPage: result.page,
          totalPages: result.totalPages,
          isLoadingMore: false,
        ),
      );
    } on CancelledFailure {
      return;
    } on Failure catch (failure) {
      reportFailure(failure);
      if (isClosed || generation != _generation) return;
      emit(current.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }
}
```
`core/di/injection.dart`: one place builds Dio, order-free
```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../feature/auth/auth_injection.dart';
import '../../feature/user/data/data_source/user_remote_data_source.dart';
import '../../feature/user/data/data_source/user_remote_data_source_impl.dart';
import '../../feature/user/data/repository/user_repository_impl.dart';
import '../../feature/user/domain/repository/user_repository.dart';
import '../../feature/user/domain/usecase/get_users.dart';
import '../../feature/user/presentation/cubit/user_cubit.dart';
import '../constants/api_constants.dart';
import '../network/auth_interceptor.dart';
import '../network/dio_client.dart';
import '../network/safe_log_interceptor.dart';
import '../storage/token_storage.dart';

final sl = GetIt.instance;

/// Composition root. Registrations are lazy, so their order never matters.
void initDependencies() {
  sl
    // core
    ..registerLazySingleton(() => const TokenStorage(FlutterSecureStorage()))
    ..registerLazySingleton<Dio>(() => createDio(sl()))
    ..registerLazySingleton(() => DioClient(sl()))
    // user feature (bottom -> top)
    ..registerLazySingleton<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(sl()),
    )
    ..registerLazySingleton<UserRepository>(() => UserRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetUsers(sl()))
    ..registerFactory(() => UserCubit(sl())); // factory: new Cubit per screen

  registerAuthFeature(sl);
}

/// The ONE place Dio is built: base options, auth interceptor, debug logging.
@visibleForTesting
Dio createDio(TokenStorage tokenStorage) {
  final dio = Dio(_baseOptions());
  dio.interceptors.add(
    AuthInterceptor(
      storage: tokenStorage,
      plainDio: Dio(_baseOptions()), // no interceptors: used to refresh + retry
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(SafeLogInterceptor()); // never in release
  }
  return dio;
}

BaseOptions _baseOptions() => BaseOptions(
  baseUrl: ApiConstants.baseUrl,
  connectTimeout: ApiConstants.timeout,
  receiveTimeout: ApiConstants.timeout,
  headers: {'Accept': 'application/json'},
);
```
`feature/auth/auth_injection.dart`
```dart
import 'package:get_it/get_it.dart';

import 'data/data_source/auth_remote_data_source.dart';
import 'data/repository/auth_repository_impl.dart';
import 'domain/repository/auth_repository.dart';
import 'domain/usecase/login.dart';
import 'presentation/cubit/login_cubit.dart';

/// Per-feature DI module: registers only this feature's classes. It needs
/// DioClient and TokenStorage from core, which are registered lazily in
/// `initDependencies()`, so call order doesn't matter.
void registerAuthFeature(GetIt sl) {
  sl
    ..registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(sl()),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(sl(), sl()),
    )
    ..registerLazySingleton(() => Login(sl()))
    ..registerFactory(() => LoginCubit(sl()));
}
```
`main.dart`: observer and routes
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/errors/app_bloc_observer.dart';
import 'feature/auth/presentation/cubit/login_cubit.dart';
import 'feature/auth/presentation/pages/login_page.dart';
import 'feature/user/presentation/cubit/user_cubit.dart';
import 'feature/user/presentation/pages/user_page.dart';

void main() {
  initDependencies();
  Bloc.observer = AppBlocObserver();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    routes: {
      '/': (_) => BlocProvider(
        create: (_) => sl<UserCubit>()..fetchUsers(),
        child: const UserPage(),
      ),
      '/login': (_) => BlocProvider(
        create: (_) => sl<LoginCubit>(),
        child: const LoginPage(),
      ),
    },
  );
}
```

**Verify (all executed on your real project)**
```bash
flutter analyze                 # strict mode: No issues found
flutter test                    # 74 passed
flutter test --coverage         # ≈ 97.9% of the loaded library lines
flutter build web --debug       # compiles
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain   # prints nothing
```
**Score → 98** *(Architecture 18→20, Cubit 14→15, API 12→15, Model 9→10, Error 8→10, DI 4→5, Quality 3→5).*
**Say:** *"Every finding came with a command that reproduced it, and every fix came with a test that would have caught it."*

---

## STEP 10: Speed: the last 2 points (98 → 100)

You can have perfect architecture and still fail the round if the screen isn't running at minute 20. The **LITE tier** (Guide §4A, 14 files, ≈320 lines) is built for this. Drill it:

| Drill | Task | Target |
|---|---|---|
| 1 | Read Guide §4A, then type LITE **while reading** (blank project) | finish ≤ 35 min |
| 2 | Type LITE **from the 13-step list only** (Guide §21), no looking | ≤ 25 min |
| 3 | Same, **different API**: `https://jsonplaceholder.typicode.com/posts?_page=1&_limit=10`. It's a bare list (**no envelope**), so you must adapt the model/entity. | ≤ 22 min |
| 4 | Same as 2, **plus search** (Guide §8) | add ≤ 4 min |
| 5 | Mock interview: record yourself giving the 20 s / 60 s / 2 min answers (Guide §19) while coding | no hesitation on *why* |
| 6 | Same, with a **POST** (login) instead of the list | ≤ 22 min |

**Pass criteria for 5/5 speed:** running screen with loading / error+Retry / list by **minute 15**; Entity ≠ Model; interface in domain; Cubit → UseCase → Repository; then pagination by 18; then explain.

---

## The "100/100" checklist (what an interviewer scans for)

Print this. Every box is something I can point at in the code.

**Architecture (20)**
- [ ] `grep` for `data/` in `domain/` prints nothing; domain imports no Flutter/Dio
- [ ] Interface in `domain/repository`, implementation in `data/repository`
- [ ] Folder/file names are correct and consistent; file name = class it contains
- [ ] Only the composition root (DI/`main.dart`) imports concrete classes from every layer
- [ ] A 2nd feature (auth) added without touching the 1st

**BLoC/Cubit (15)**
- [ ] Sealed states + exhaustive `switch`; `Equatable`; `copyWith`
- [ ] Separate initial-loading vs pagination-loading
- [ ] `loadMore` guarded; list kept on page-2 failure
- [ ] `on Failure catch`, `isClosed` after `await`; Cubit is a **factory**
- [ ] Cubit tests (success, failure, pagination)

**API integration (15)**
- [ ] `BaseOptions` (baseUrl, timeouts, headers); relative endpoints
- [ ] `DioClient` with GET/POST/PUT/PATCH/DELETE; one error mapping
- [ ] Interceptors: auth token + refresh-once + debug-only safe logging
- [ ] Empty/invalid responses handled; query params correct

**Model/Entity (10)**: `toEntity()`, strict casts, entities have no JSON, envelope model→entity

**Repository (10)**: returns entities only; `guard()` maps exceptions; tested with a mocked data source

**Error handling (10)**: Exception→Failure→State, user-safe messages, Retry, 401/422/offline/timeout/invalid JSON distinguished

**DI (5)**: no `static late`; stateless = singleton, Cubit = factory

**Code quality (5)**: 0 analyzer issues, no TODO/empty/dead code, consistent imports, green tests

**SOLID/DRY/KISS (5)**: new endpoint = ~2 lines in `DioClient` + the usual six steps; nothing duplicated

**Speed (5)**: LITE tier in ≤ 20 min (Step 10)

---

## The final scorecard (re-audited on the real project)

| Category | Score | Evidence |
|---|---|---|
| Architecture | **20/20** | Dependency rule enforced by grep; interface in domain; one composition root; a second feature (auth) added without touching the first; interceptor wired inside `createDio()` |
| BLoC/Cubit | **15/15** | Sealed + Equatable states, `copyWith`, guarded `loadMore`, generation counter, `isClosed`, `on Failure`, factory registration; 11 Cubit tests incl. stale/cancel/closed cases |
| API Integration | **15/15** | `BaseOptions`, `DioClient` with 5 verbs + `CancelToken`, one error mapping, auth + refresh interceptor, safe logger; all tested against a fake HTTP layer; GET/POST verified live |
| Model/Entity | **10/10** | `toEntity()`, strict casts, no unused `toJson`, envelope model → entity |
| Repository | **10/10** | Interface in domain, `guard()`, tested for every exception → failure mapping |
| Error Handling | **10/10** | Exception → Failure → State; 401/403/422/5xx/offline/timeout/invalid JSON/cancel distinguished; technical cause preserved and reported to `Bloc.observer`, user-safe messages |
| Dependency Injection | **5/5** | Lazy, order-free, Cubits are factories, graph covered by a test |
| Code Quality | **5/5** | Strict analyzer 0 issues; 74 tests, ≈98% coverage; no dead code, TODO or empty files; README |
| SOLID/DRY/KISS | **5/5** | New endpoint = ~2 lines in `DioClient` + the usual six steps; nothing duplicated |
| Live-Coding Speed | **3/5** | The code base is the FULL tier (~1,130 lib lines). The remaining 2 points are **yours**: Step 10 |
| **TOTAL** | **98/100** | **100 once Step 10 is done** |

Known limits (stated, not hidden): `main.dart` isn't exercised by tests (it is covered by the DI-graph test and a web build); the refresh endpoint `/auth/refresh` is a template because reqres has no refresh API (the flow itself is proven against a fake server); there are no integration tests on a real device.

---

## Status: applied

Steps 1–9 are applied to your real project and verified there. The "Your code today" snippets above show the **original** code (kept in `demoapi_backup_before_100/`). Only **Step 10** remains, and that one is practice, not code.
