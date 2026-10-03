# Flutter API Integration — Clean Architecture + BLoC/Cubit
## 20-Minute Live Coding Interview Guide

> **How this book was built.** Every code block in sections 4–17 is pulled from real projects that were compiled with `flutter analyze` (0 issues) and tested (**74 passing tests, ≈98% line coverage**: cubit, repository, data source, `DioClient`, auth interceptor, token storage, DI graph, pages, login). The GET and POST/login flows were also run end-to-end against `https://reqres.in/api` (page 2 → 6 users; `POST /login` with a missing password → `400 "Missing password"` → mapped correctly; `/users/9999` → 404; unreachable host → `NetworkFailure`). Nothing here is pseudo-code unless it says **(illustrative)**.
>
> **Dependencies:** `flutter_bloc ^9`, `dio ^5`, `equatable ^3`, `get_it ^9` (optional), `flutter_secure_storage` (auth only). Dev: `bloc_test`, `mocktail`. Optional: `bloc_concurrency`.
> `flutter pub add flutter_bloc dio equatable get_it` · `flutter pub add --dev bloc_test mocktail`

---

## Read this first: the two tiers (honesty about 20 minutes)

The full production-quality reference below is **~790 lines** for one feature (plus ~350 for the auth feature and its infrastructure). Nobody types that in 20 minutes. So there are two tiers:

| Tier | What | Lines | When |
|---|---|---|---|
| **LITE: you type this** | Same layers (Entity → Model → Repository interface → DataSource → RepositoryImpl → UseCase → Cubit → UI), `toEntity()` mapping, one `Failure` class, manual DI, retry, and pagination | **≈ 320** (≈ 270 before pagination) | The 20-minute round |
| **FULL: you explain this** | `DioClient` (5 verbs), `AppException`→`Failure` hierarchy + `guard()`, `Equatable` states, `loadMoreFailed`, stale-response guard, cause-preserving failures + logging hook, cancellation, GetIt, interceptors, tests | ≈ 790 | "How would you make this production-ready?" and for take-home / pair-programming rounds |

The architecture, layer names, and data flow are **identical** in both. LITE is not "worse architecture": it is the same architecture with less ceremony. You say out loud what you'd add. Sections 4A/4B show both; section 21 is the minute-by-minute script.

**Priority order (memorize):** `Correctness → Clean Architecture → Readability → Speed → Explainability.` A working screen with the right layers beats a half-finished perfect one. **Get the happy path on screen first, then harden.**

---

## SECTION 1 — The Master Architecture

### 1.1 The call chain

```text
                 ┌─────────────────┐
                 │       UI        │   Screen/Widget: draws state, forwards taps
                 │  Screen/Widget  │
                 └────────┬────────┘
                          │ ①
                          ▼
                 ┌─────────────────┐
                 │   Cubit / BLoC  │   Holds screen state, decides WHICH state to show
                 │   State Mgmt    │
                 └────────┬────────┘
                          │ ②
                          ▼
                 ┌─────────────────┐
                 │     UseCase     │   One business action: "get users"
                 │ Business Action │
                 └────────┬────────┘
                          │ ③
                          ▼
                 ┌─────────────────┐
                 │ Repository      │   Contract (abstract). Lives in DOMAIN.
                 │   Interface     │
                 └────────┬────────┘
                          │ ④  (implemented by)
                          ▼
                 ┌─────────────────┐
                 │ RepositoryImpl  │   Lives in DATA. Model→Entity, Exception→Failure
                 └────────┬────────┘
                          │ ⑤
                          ▼
                 ┌─────────────────┐
                 │ RemoteDataSource│   Knows endpoints + JSON. Returns Models.
                 └────────┬────────┘
                          │ ⑥
                          ▼
                 ┌─────────────────┐
                 │      Dio        │   HTTP client (baseUrl, timeouts, interceptors)
                 └────────┬────────┘
                          │ ⑦
                          ▼
                 ┌─────────────────┐
                 │    REST API     │
                 └─────────────────┘
```

**Explaining every arrow (request direction):**

| # | Arrow | What happens | Why this boundary exists |
|---|---|---|---|
| ① | UI → Cubit | `context.read<UserCubit>().loadMore()` | UI never fetches data or holds business state. It forwards intent. |
| ② | Cubit → UseCase | `_getUsers(page: 2)` | Cubit asks for a business action, not an HTTP call. Easy to mock in tests. |
| ③ | UseCase → Repository (interface) | `_repository.getUsers(page: 2)` | The use case depends on an *abstraction*, so it is blind to REST/DB/cache. |
| ④ | Interface ⇢ Impl | DI wires `UserRepositoryImpl` behind `UserRepository` | Dependency Inversion: data implements what domain defines. |
| ⑤ | RepositoryImpl → DataSource | `_remote.getUsers(page: 2)` | Repository chooses *where* data comes from (remote now, cache/local later). |
| ⑥ | DataSource → Dio | `_dio.get('/users', queryParameters: {'page': 2})` | Only the data source knows endpoint paths and JSON shapes. |
| ⑦ | Dio → API | HTTP request | Network, auth headers, timeouts, logging live in Dio config/interceptors. |

### 1.2 The response flow

```text
API
 ↓  ⓐ
JSON            {"page":2,"total_pages":2,"data":[{"id":7,"first_name":"Michael",...}]}
 ↓  ⓑ
Model           UsersResponseModel / UserModel      (mirrors the JSON: snake_case, strict types)
 ↓  ⓒ
Entity          PagedUsers / User                   (mirrors the business: no JSON anywhere)
 ↓  ⓓ
Repository      returns Entity, converts Exception → Failure
 ↓  ⓔ
UseCase         passes through (or applies a rule)
 ↓  ⓕ
Cubit           chooses the state
 ↓  ⓖ
State           UserLoaded(users, page, hasNext, ...)
 ↓  ⓗ
UI              BlocBuilder draws it
```

| # | Arrow | Explanation |
|---|---|---|
| ⓐ | API → JSON | Dio decodes the body into `Map<String, dynamic>`. Invalid JSON surfaces as `DioException(unknown, FormatException)`. |
| ⓑ | JSON → Model | `UsersResponseModel.fromJson(json)`: strict `as int` / `as String`. A wrong shape throws `TypeError`. |
| ⓒ | Model → Entity | `model.toEntity()`: **the anti-corruption boundary.** Backend renames never reach the app. |
| ⓓ | Entity out of Repository | Only entities (or `Failure`s) leave `data/`. No `Dio`, no `Model` above this line. |
| ⓔ | → UseCase | Business rules can run here. |
| ⓕ | → Cubit | `emit(UserLoaded(...))` or `emit(UserError(failure.message))`. |
| ⓖ | State → UI | Immutable snapshot of "what the screen shows". |
| ⓗ | UI draws | `switch (state)` is exhaustive (sealed) so no state is forgotten. |

### 1.3 The dependency rule (the part interviewers actually grade)

The *call* arrows above go downward. The *import* arrows go **inward**:

```text
 presentation ──imports──▶ domain ◀──imports── data
 (Cubit, UI)              (entities, repo        (models, data sources,
                           interface, usecase)    repo impl, Dio)
                                  │
                       imports NOTHING from the
                       other layers, Flutter or Dio
```

| Folder | Responsibility | Depends On |
|---|---|---|
| `presentation` | UI + state (Cubit, pages, widgets) | `domain` |
| `domain` | Business objects + contracts (entities, repository interface, use cases) | **nothing** (pure Dart + equatable) |
| `data` | API/DB implementation (models, data sources, repository impl) | `domain` (+ `core`, Dio) |
| `core` | Shared infrastructure (errors, network, DI, constants) | framework / external packages |

One-line test you can run any time (must print nothing):

```bash
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain
```

---

## SECTION 2 — Folder Structure

**FULL tier tree** (LITE omits `exceptions.dart`, `dio_client.dart`, `di/`, `widgets/`, and merges data-source interface + impl into one file):

```text
lib/
│
├── core/
│   ├── constants/
│   │   └── api_constants.dart          base URL, paths, timeout
│   │
│   ├── network/
│   │   └── dio_client.dart             5 verbs + DioException → AppException (once)
│   │
│   ├── errors/
│   │   ├── exceptions.dart             thrown by data layer (ServerException, NetworkException…)
│   │   └── failures.dart               seen by Cubit (Failure types) + guard()
│   │
│   └── di/
│       └── injection.dart              GetIt wiring (or manual DI in main.dart)
│
├── feature/
│   └── user/
│       ├── data/
│       │   ├── data_source/            user_remote_data_source.dart (+ _impl.dart)
│       │   ├── model/                  user_model.dart, users_response_model.dart
│       │   └── repository/             user_repository_impl.dart
│       │
│       ├── domain/
│       │   ├── entity/                 user.dart, paged_users.dart
│       │   ├── repository/             user_repository.dart (abstract)
│       │   └── usecase/                get_users.dart
│       │
│       └── presentation/
│           ├── cubit/                  user_cubit.dart, user_state.dart
│           ├── pages/                  user_page.dart
│           └── widgets/                user_tile.dart, error_view.dart, load_more_footer.dart
│
└── main.dart
```

| Folder | One-line job |
|---|---|
| `core/constants` | Strings/numbers shared everywhere (URLs, timeouts). Never inline a URL in a data source. |
| `core/network` | The only code that imports Dio's error types. |
| `core/errors` | The vocabulary of failure: exceptions in `data`, failures above. |
| `core/di` | The only file allowed to import concrete classes from every layer. |
| `feature/<name>/data` | How we get the data: JSON models, HTTP calls, mapping. |
| `feature/<name>/domain` | What the app needs: entities, contracts, business actions. No I/O. |
| `feature/<name>/presentation` | What the user sees: Cubit + widgets. |

Do **not** add `utils/`, `helpers/`, `services/`, `bloc/` + `cubit/` double folders. Each extra folder is typing time and a question you'll have to answer.

---

## SECTION 3 — The 20-Minute Implementation Plan (stopwatch)

> Rule: **after minute 13 the app must run.** Everything after is bonus/hardening. If you are behind at any checkpoint, *cut* (see the "cut list"), never rush the layers.

| Time | Do | Files (LITE) | Say out loud |
|---|---|---|---|
| **0–2 min** | Read the API response. Add deps. Create folders. | `flutter pub add flutter_bloc dio` · `api_constants.dart` | "GET `/users?page=` returns `{page, total_pages, data[]}`. I'll model it in three layers: JSON model, domain entity, state." |
| **2–5 min** | Domain + Models | `user.dart`, `paged_users.dart`, `user_model.dart` (+`toEntity`), `users_response_model.dart`, `user_repository.dart` | "Entity is pure business. Model mirrors JSON. Interface lives in domain so domain never imports data." |
| **5–8 min** | Data layer | `failure.dart`, `user_remote_data_source.dart` (interface + impl), `user_repository_impl.dart` | "Data source owns the endpoint and parsing; repository maps Model→Entity." |
| **8–11 min** | Use case + Cubit + States | `get_users.dart`, `user_state.dart`, `user_cubit.dart` (`fetchUsers` only) | "Sealed states so the UI `switch` is exhaustive. Cubit never touches Dio." |
| **11–15 min** | UI + DI + RUN | `user_page.dart` (loading / error+retry / list), `main.dart` (manual DI) → **press ▶︎** | "Composition root in `main.dart`: the only place that knows concrete classes." |
| **15–18 min** | Add what they ask | `loadMore()` + footer (pagination) **or** search **or** pull-to-refresh | "`loadMore` ignores calls while loading or on the last page." |
| **18–20 min** | Explain | Architecture, SOLID, error handling, *why* Cubit/Repository/UseCase | Use section 19's scripts. |

### The cut list (what to drop when behind)

| Behind at… | Cut | Say instead |
|---|---|---|
| 8 min | Data-source **interface** (keep only the class) | "I'd put an interface here for testing; skipping for time." |
| 11 min | Use case (call repository from Cubit) | "In production I'd add the use case as the seam for business rules." (try hard to keep: it is the expected layering) |
| 13 min | `copyWith`/Equatable, error retry button | "States would be Equatable; retry is a one-liner." |
| 15 min | Pagination | Describe `currentPage/totalPages/isLoadingMore/hasReachedMax` verbally |
| Never cut | Entity vs Model separation · interface in domain · Cubit → UseCase → Repository · error state in the UI | |

### Typing-speed tricks (use your IDE, don't type boilerplate)
- **Constructors:** declare `final` fields, then `Ctrl/Cmd + .` → *Create constructor* / *Add required keyword*.
- `stless` snippet for widgets; `Ctrl + .` → *Wrap with BlocBuilder*.
- **Don't write `toJson` unless you POST that model.**
- Write the `sealed class` states first: the compiler then tells you every `switch` you must complete.
- Paste the sample JSON into a comment first; field names are then a copy-paste, not a guess.

---

## SECTION 4 — Basic API: `GET /api/users?page=1`, from `main.dart` to UI

Sample response (paste this into a comment at minute 0; it is your spec):

```json
{
  "page": 1, "per_page": 6, "total": 12, "total_pages": 2,
  "data": [
    { "id": 1, "email": "george.bluth@reqres.in", "first_name": "George",
      "last_name": "Bluth", "avatar": "https://reqres.in/img/faces/1-image.jpg" }
  ]
}
```

### 4A. LITE: the version you type (compiles, 0 analyzer issues, widget-tested)

Typing order = dependency order: **domain → data → presentation → main**. Each file is followed by what to say.

**`lib/core/constants/api_constants.dart`**
```dart
class ApiConstants {
  static const baseUrl = 'https://reqres.in/api';
  static const users = '/users';
}
```

**`lib/core/errors/failure.dart`**: *"One failure type carrying a user-safe message. In production this becomes a sealed hierarchy."*
```dart
class Failure implements Exception {
  const Failure(this.message);

  final String message;
}
```

**`lib/feature/user/domain/entity/user.dart`**: *"Entity: pure business object. No JSON, no Flutter."*
```dart
class User {
  const User({
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
}
```

**`lib/feature/user/domain/entity/paged_users.dart`**: *"A page of users is a business concept, so it lives in domain, not in data. This is the file that was in the wrong layer in the audit."*
```dart
import 'user.dart';

class PagedUsers {
  const PagedUsers({required this.users, required this.page, required this.totalPages});

  final List<User> users;
  final int page;
  final int totalPages;
}
```

**`lib/feature/user/data/model/user_model.dart`**: *"Model mirrors the API and knows JSON. `toEntity()` is the boundary."*
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

  User toEntity() =>
      User(id: id, email: email, firstName: firstName, lastName: lastName, avatar: avatar);
}
```

**`lib/feature/user/data/model/users_response_model.dart`**: *"The envelope: pagination metadata + list."*
```dart
import '../../domain/entity/paged_users.dart';
import 'user_model.dart';

class UsersResponseModel {
  const UsersResponseModel({required this.page, required this.totalPages, required this.data});

  final int page;
  final int totalPages;
  final List<UserModel> data;

  factory UsersResponseModel.fromJson(Map<String, dynamic> json) => UsersResponseModel(
    page: json['page'] as int,
    totalPages: json['total_pages'] as int,
    data: (json['data'] as List).map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList(),
  );

  PagedUsers toEntity() =>
      PagedUsers(users: data.map((m) => m.toEntity()).toList(), page: page, totalPages: totalPages);
}
```

**`lib/feature/user/domain/repository/user_repository.dart`**: *"Contract defined by the domain. Returns entities only."*
```dart
import '../entity/paged_users.dart';

abstract interface class UserRepository {
  Future<PagedUsers> getUsers({required int page});
}
```

**`lib/feature/user/data/data_source/user_remote_data_source.dart`**: *interface + implementation in one file (LITE shortcut; FULL splits them into `user_remote_data_source.dart` and `user_remote_data_source_impl.dart`).* "Only this class knows the endpoint and converts `DioException` into a user-safe `Failure`."
```dart
import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/failure.dart';
import '../model/users_response_model.dart';

abstract interface class UserRemoteDataSource {
  Future<UsersResponseModel> getUsers({required int page});
}

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  const UserRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<UsersResponseModel> getUsers({required int page}) async {
    try {
      final response = await _dio.get(ApiConstants.users, queryParameters: {'page': page});
      return UsersResponseModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Failure(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout => 'Request timed out.',
        DioExceptionType.connectionError => 'No internet connection.',
        DioExceptionType.badResponse => 'Server error (${e.response?.statusCode}).',
        _ => 'Something went wrong.',
      });
    }
  }
}
```

**`lib/feature/user/data/repository/user_repository_impl.dart`**: *"Implements the domain contract; maps Model → Entity."*
```dart
import '../../domain/entity/paged_users.dart';
import '../../domain/repository/user_repository.dart';
import '../data_source/user_remote_data_source.dart';

class UserRepositoryImpl implements UserRepository {
  const UserRepositoryImpl(this._remote);

  final UserRemoteDataSource _remote;

  @override
  Future<PagedUsers> getUsers({required int page}) async =>
      (await _remote.getUsers(page: page)).toEntity();
}
```

**`lib/feature/user/domain/usecase/get_users.dart`**: *"One business action, one file. `call()` lets me invoke it like a function."*
```dart
import '../entity/paged_users.dart';
import '../repository/user_repository.dart';

class GetUsers {
  const GetUsers(this._repository);

  final UserRepository _repository;

  Future<PagedUsers> call({required int page}) => _repository.getUsers(page: page);
}
```

**`lib/feature/user/presentation/cubit/user_state.dart`**: *"Sealed: the UI `switch` must handle every state or it will not compile."*
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
  const UserLoaded({
    required this.users,
    required this.page,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<User> users;
  final int page;
  final bool hasNext;
  final bool isLoadingMore;

  UserLoaded copyWith({List<User>? users, int? page, bool? hasNext, bool? isLoadingMore}) =>
      UserLoaded(
        users: users ?? this.users,
        page: page ?? this.page,
        hasNext: hasNext ?? this.hasNext,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

class UserError extends UserState {
  const UserError(this.message);

  final String message;
}
```

**`lib/feature/user/presentation/cubit/user_cubit.dart`**: *"Cubit only orchestrates. `loadMore` is guarded against double calls and the last page."*
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/usecase/get_users.dart';
import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  UserCubit(this._getUsers) : super(const UserInitial());

  final GetUsers _getUsers;

  Future<void> fetchUsers() async {
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1);
      emit(
        UserLoaded(
          users: result.users,
          page: result.page,
          hasNext: result.page < result.totalPages,
        ),
      );
    } on Failure catch (f) {
      emit(UserError(f.message));
    } catch (_) {
      emit(const UserError('Something went wrong.'));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! UserLoaded || current.isLoadingMore || !current.hasNext) {
      return;
    }
    emit(current.copyWith(isLoadingMore: true));
    try {
      final result = await _getUsers(page: current.page + 1);
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          page: result.page,
          hasNext: result.page < result.totalPages,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      emit(current.copyWith(isLoadingMore: false)); // keep list, stop spinner
    }
  }
}
```

**`lib/feature/user/presentation/pages/user_page.dart`**: *"The `switch` covers loading, error with retry, and the list. Reaching the footer asks for the next page."*
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/user_cubit.dart';
import '../cubit/user_state.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Users')),
    body: BlocBuilder<UserCubit, UserState>(
      builder: (context, state) => switch (state) {
        UserInitial() || UserLoading() => const Center(child: CircularProgressIndicator()),
        UserError(:final message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              ElevatedButton(
                onPressed: context.read<UserCubit>().fetchUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        UserLoaded() => ListView.builder(
          itemCount: state.users.length + (state.hasNext ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == state.users.length) {
              // footer built = user reached the end -> next page
              final cubit = context.read<UserCubit>();
              Future.microtask(cubit.loadMore);
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final user = state.users[i];
            return ListTile(
              leading: CircleAvatar(
                foregroundImage: NetworkImage(user.avatar),
                onForegroundImageError: (_, _) {},
                child: const Icon(Icons.person),
              ),
              title: Text('${user.firstName} ${user.lastName}'),
              subtitle: Text(user.email),
            );
          },
        ),
      },
    ),
  );
}
```

**`lib/main.dart`**: *composition root + manual DI.* "The only place that knows concrete classes. `..fetchUsers()` kicks off the first load."
```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/api_constants.dart';
import 'feature/user/data/data_source/user_remote_data_source.dart';
import 'feature/user/data/repository/user_repository_impl.dart';
import 'feature/user/domain/usecase/get_users.dart';
import 'feature/user/presentation/cubit/user_cubit.dart';
import 'feature/user/presentation/pages/user_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Composition root: the only place that knows the concrete classes.
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final repository = UserRepositoryImpl(UserRemoteDataSourceImpl(dio));

    return MaterialApp(
      home: BlocProvider(
        create: (_) => UserCubit(GetUsers(repository))..fetchUsers(),
        child: const UserPage(),
      ),
    );
  }
}
```

**▶︎ RUN here.** If page 1 shows, you are at minute ~13. Everything after is bonus.

> **Why the footer trigger (`Future.microtask(cubit.loadMore)`) instead of a `ScrollController`?** reqres returns 6 users per page. On a tall phone, 6 tiles don't fill the screen: nothing scrolls, so a scroll listener never fires and page 2 is never requested. Building the footer = "the user can see the end", on any screen size. `Future.microtask` avoids calling `emit` while the framework is building. The Cubit's guard makes the repeated calls harmless. (The `ScrollController` version is in section 7.)

### 4B. FULL: the production upgrade (what you *say* you'd do; every file compiled and tested)

What changes vs LITE, and why:

| LITE | FULL | Why |
|---|---|---|
| `Failure(message)` thrown from the data source | `AppException` (data) → `Failure` (domain/UI) + `guard()` in the repository | Cubit can react differently to 401 vs offline vs 422; Dio never leaks upward |
| Dio used directly in each data source | `DioClient`: one place for 5 verbs + error mapping | DRY: every new endpoint is 2–3 lines |
| States without equality | `Equatable` + `loadMoreFailed` + `hasReachedMax` | No duplicate rebuilds; testable; page-2 failure keeps the list |
| `catch (_)` | `on Failure catch` + `if (isClosed) return;` + a **generation counter** | Don't hide programmer bugs; no emit after close; a stale response (Retry spam, refresh during `loadMore`) is dropped |
| Failure = message only | Failure also carries `cause` + `stackTrace`; `FailureReporting` mixin forwards them to `Bloc.observer` | Users see a safe message, your logger/crash tool sees the real error |
| Request can't be cancelled | `CancelToken` on every `DioClient` verb → `CancelledFailure`, ignored by Cubits | A cancelled request is not an error |
| Manual DI | GetIt (Cubit as **factory**) | Scales to many features; test overrides |
| Inline tile / footer / error | `UserTile`, `ErrorView`, `LoadMoreFooter` widgets | Small widgets, reuse |

**`core/constants/api_constants.dart`**
```dart
abstract final class ApiConstants {
  static const baseUrl = 'https://reqres.in/api';

  static const users = '/users';
  static const login = '/login';

  static const timeout = Duration(seconds: 10);
}
```

**`core/errors/exceptions.dart`**: thrown by the **data layer** only.
```dart
/// Thrown by the data layer (DioClient / data sources). Never reaches the UI.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;
}

/// The server answered with a non-2xx status code.
class ServerException extends AppException {
  const ServerException(super.message, {this.statusCode});

  final int? statusCode;
}

/// No internet, timeout, DNS failure...
class NetworkException extends AppException {
  const NetworkException(super.message);
}

/// 200 OK but the body is not valid JSON.
class ParsingException extends AppException {
  const ParsingException(super.message);
}

/// The caller cancelled the request (CancelToken). Not an error to show.
class CancelledException extends AppException {
  const CancelledException(super.message);
}
```

**`core/errors/failures.dart`**: what the **domain/UI** understands, plus `guard()`, the single Exception→Failure converter. Failures carry the technical `cause`/`stackTrace` (never shown) so nothing is swallowed.
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

**`core/errors/report_failure.dart`** and **`app_bloc_observer.dart`**: the logging hook. A Cubit calls `reportFailure(failure)`; parsing/unknown failures reach `Bloc.observer.onError`, the one place to plug Crashlytics/Sentry. Expected failures (offline, 401, 422) have no cause and are not reported.
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
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Central error sink for every Cubit/Bloc. Replace `debugPrint` with your
/// crash reporter (e.g. Crashlytics.recordError) for production.
class AppBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) debugPrint('[${bloc.runtimeType}] $error\n$stackTrace');
    super.onError(bloc, error, stackTrace);
  }
}
```

**`core/network/dio_client.dart`**: all verbs, one `_send`, one mapping.
```dart
import 'package:dio/dio.dart';

import '../errors/exceptions.dart';

/// Thin wrapper over Dio: one place for every HTTP verb and for
/// DioException -> AppException mapping.
class DioClient {
  const DioClient(this._dio);

  final Dio _dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _send(
    () => _dio.get<dynamic>(
      path,
      queryParameters: query,
      cancelToken: cancelToken,
    ),
  );

  Future<dynamic> post(String path, {Object? data, CancelToken? cancelToken}) =>
      _send(
        () => _dio.post<dynamic>(path, data: data, cancelToken: cancelToken),
      );

  Future<dynamic> put(String path, {Object? data, CancelToken? cancelToken}) =>
      _send(
        () => _dio.put<dynamic>(path, data: data, cancelToken: cancelToken),
      );

  Future<dynamic> patch(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) => _send(
    () => _dio.patch<dynamic>(path, data: data, cancelToken: cancelToken),
  );

  Future<dynamic> delete(String path, {CancelToken? cancelToken}) =>
      _send(() => _dio.delete<dynamic>(path, cancelToken: cancelToken));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  AppException _toException(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const NetworkException(
      'Request timed out. Please try again.',
    ),
    DioExceptionType.connectionError => const NetworkException(
      'No internet connection.',
    ),
    DioExceptionType.cancel => const CancelledException('Request cancelled.'),
    DioExceptionType.badResponse => ServerException(
      _bodyMessage(e.response) ?? _defaultMessage(e.response?.statusCode),
      statusCode: e.response?.statusCode,
    ),
    // Dio wraps a JSON decoding error as `unknown` + FormatException.
    DioExceptionType.unknown when e.error is FormatException =>
      const ParsingException('Invalid response from server.'),
    _ => const NetworkException('Network error. Please try again.'),
  };

  /// reqres returns {"error": "..."}; many APIs use {"message": "..."}.
  String? _bodyMessage(Response<dynamic>? response) {
    final data = response?.data;
    if (data is! Map) return null;
    final message = data['error'] ?? data['message'];
    return message is String ? message : null;
  }

  String _defaultMessage(int? code) => switch (code) {
    400 => 'Bad request.',
    401 => 'Please login again.',
    403 => 'You do not have access.',
    404 => 'Not found.',
    422 => 'Validation failed.',
    final int c when c >= 500 => 'Server error. Please try later.',
    _ => 'Unexpected server response ($code).',
  };
}
```

**`domain/entity/user.dart`** and **`domain/entity/paged_users.dart`** (Equatable, `fullName`, `hasNext`)
```dart
import 'package:equatable/equatable.dart';

class User extends Equatable {
  const User({
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

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [id, email, firstName, lastName, avatar];
}
```
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

*(Unchanged from LITE: `user_repository.dart`, `get_users.dart`. Models: same as LITE plus optional `toJson` on `UserModel` and `perPage`/`total` on the response model.)*

**`data/data_source/user_remote_data_source.dart`** (interface) and **`..._impl.dart`**
```dart
import '../model/users_response_model.dart';

abstract interface class UserRemoteDataSource {
  Future<UsersResponseModel> getUsers({required int page});
}
```
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

**`data/repository/user_repository_impl.dart`**: three lines, because `guard()` does the mapping.
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

**`presentation/cubit/user_state.dart`**
```dart
import 'package:equatable/equatable.dart';

import '../../domain/entity/user.dart';

sealed class UserState extends Equatable {
  const UserState();

  @override
  List<Object?> get props => [];
}

class UserInitial extends UserState {
  const UserInitial();
}

/// First page is loading (full-screen spinner).
class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  const UserLoaded({
    required this.users,
    required this.currentPage,
    required this.totalPages,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<User> users;
  final int currentPage;
  final int totalPages;
  final bool isLoadingMore; // next page is loading (footer spinner)
  final bool loadMoreFailed; // next page failed (footer retry button)

  bool get hasReachedMax => currentPage >= totalPages;

  UserLoaded copyWith({
    List<User>? users,
    int? currentPage,
    int? totalPages,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => UserLoaded(
    users: users ?? this.users,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );

  @override
  List<Object?> get props => [
    users,
    currentPage,
    totalPages,
    isLoadingMore,
    loadMoreFailed,
  ];
}

class UserError extends UserState {
  const UserError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
```

**`presentation/cubit/user_cubit.dart`**
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

**`presentation/widgets/user_tile.dart`**, **`error_view.dart`**, **`load_more_footer.dart`**
```dart
import 'package:flutter/material.dart';

import '../../domain/entity/user.dart';

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(
      foregroundImage: NetworkImage(user.avatar),
      onForegroundImageError: (_, _) {}, // broken URL -> fallback icon
      child: const Icon(Icons.person),
    ),
    title: Text(user.fullName),
    subtitle: Text(user.email),
  );
}
```
```dart
import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
```
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/user_cubit.dart';

/// Last list item. The moment it is built (= user reached the end) it asks the
/// Cubit for the next page. Works even when page 1 doesn't fill the screen.
class LoadMoreFooter extends StatefulWidget {
  const LoadMoreFooter({super.key, required this.failed});

  final bool failed;

  @override
  State<LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<LoadMoreFooter> {
  @override
  void initState() {
    super.initState();
    // Not during build: emitting inside initState would call setState in build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UserCubit>().loadMore();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: widget.failed
          ? TextButton(
              onPressed: context.read<UserCubit>().loadMore,
              child: const Text('Failed to load. Tap to retry'),
            )
          : const CircularProgressIndicator(),
    ),
  );
}
```

**`presentation/pages/user_page.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/user_cubit.dart';
import '../cubit/user_state.dart';
import '../widgets/error_view.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/user_tile.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Users'),
      actions: [
        IconButton(
          icon: const Icon(Icons.login),
          tooltip: 'Login',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ],
    ),
    body: BlocBuilder<UserCubit, UserState>(
      builder: (context, state) => switch (state) {
        UserInitial() ||
        UserLoading() => const Center(child: CircularProgressIndicator()),
        UserError(:final message) => ErrorView(
          message: message,
          onRetry: context.read<UserCubit>().fetchUsers,
        ),
        UserLoaded() => _UserList(state: state),
      },
    ),
  );
}

class _UserList extends StatelessWidget {
  const _UserList({required this.state});

  final UserLoaded state;

  @override
  Widget build(BuildContext context) {
    final count = state.users.length;
    return ListView.builder(
      itemCount: state.hasReachedMax ? count : count + 1, // +1 = footer
      itemBuilder: (_, index) => index < count
          ? UserTile(user: state.users[index])
          : LoadMoreFooter(failed: state.loadMoreFailed),
    );
  }
}
```

**`core/di/injection.dart`**: GetIt. `createDio()` is the **one place** Dio is built (options + auth interceptor + debug-only logger); registrations are lazy so their order never matters; the Cubit is a `registerFactory`.
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

**`main.dart`**: observer, and the two routes (`/` users, `/login`). The users page has a login icon in its AppBar.
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

### 4C. GetIt or manual DI, decision rule

| Situation | Choose |
|---|---|
| One feature, 20 minutes | **Manual** (composition root in `main.dart`): zero setup, one place, trivial to explain |
| 2+ features, or interviewer asks "how does it scale / test overrides?" | **GetIt** (`registerLazySingleton` for stateless things, `registerFactory` for Cubits) |
| Large team, many modules | `injectable` + GetIt (codegen); mention only |

Manual DI, FULL-tier classes (verified):
```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../feature/user/data/data_source/user_remote_data_source_impl.dart';
import '../feature/user/data/repository/user_repository_impl.dart';
import '../feature/user/domain/usecase/get_users.dart';
import '../feature/user/presentation/cubit/user_cubit.dart';
import '../feature/user/presentation/pages/user_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Composition root: the ONLY place that knows every concrete class.
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.timeout,
        receiveTimeout: ApiConstants.timeout,
      ),
    );
    final repository = UserRepositoryImpl(UserRemoteDataSourceImpl(DioClient(dio)));

    return MaterialApp(
      home: BlocProvider(
        create: (_) => UserCubit(GetUsers(repository))..fetchUsers(),
        child: const UserPage(),
      ),
    );
  }
}
```

**Wiring order is always bottom-up:** `Dio → DioClient → DataSource → Repository → UseCase → Cubit`. If it doesn't compile, you wired it out of order or forgot the interface type on the left (`registerLazySingleton<UserRepository>(...)`).

---

## SECTION 5 — One pattern for every endpoint

```text
MODEL  ──▶  DATASOURCE  ──▶  REPOSITORY  ──▶  USECASE  ──▶  CUBIT/BLOC  ──▶  UI
 (JSON)      (HTTP call)     (map + errors)   (action)       (state)         (draw)
```

Every new endpoint is the **same six steps**. Only the nouns change:

| API | Request model | Response model → Entity | DataSource method | Repository / UseCase | Cubit state shape |
|---|---|---|---|---|---|
| **GET** users | none (`page` param) | `UsersResponseModel` → `PagedUsers` | `getUsers(page)` | `getUsers(page)` / `GetUsers` | **Query:** Initial → Loading → Loaded / Error |
| **GET** user details | none (`id` in path) | `UserModel` (unwrap `data`) → `User` | `getUser(id)` | `getUser(id)` / `GetUserDetails` | Query |
| **POST** login | `LoginRequestModel{email,password}` | `LoginResponseModel{token}` → `AuthSession` | `login(request)` | `login(email,password)` / `Login` | **Command:** Initial → Loading → Success / Error |
| **POST** create user | `CreateUserRequestModel{name,job}` | `CreateUserResponseModel{id,createdAt}` | `createUser(request)` | `createUser(...)` / `CreateUser` | Command |
| **PUT** update user | same request model (full resource) | none (204/200) | `updateUser(id, request)` | `updateUser` / `UpdateUser` | Command |
| **PATCH** update user | only changed fields (`Map` / nullable fields) | none | `patchUser(id, name?, job?)` | `patchUser` / `PatchUser` | Command |
| **DELETE** user | none | none (204: body is empty) | `deleteUser(id)` | `deleteUser(id)` / `DeleteUser` | Command (+ remove from the local list on success) |

**Query vs Command, the two state shapes.**
- *Query* (read): the screen **is** the data → `Loading / Loaded / Error` and the UI `switch`es.
- *Command* (write): the screen is a form; the result is a **one-time event** → `Initial / Submitting / Success / Error`. Use `BlocConsumer`: **`listener`** for one-off effects (snackbar, navigation, pop), **`builder`** for the button spinner. Never navigate from `builder`.

**Data-source methods for all five verbs** (verified; each is 2–3 lines because `DioClient` does the HTTP + error mapping):
```dart
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../feature/user/data/model/user_model.dart';

// Request models: only toJson. Response models: only fromJson (+ toEntity).
class CreateUserRequestModel {
  const CreateUserRequestModel({required this.name, required this.job});

  final String name;
  final String job;

  Map<String, dynamic> toJson() => {'name': name, 'job': job};
}

class CreateUserResponseModel {
  const CreateUserResponseModel({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;

  factory CreateUserResponseModel.fromJson(Map<String, dynamic> json) => CreateUserResponseModel(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// One method per endpoint. Every method is 2-3 lines because DioClient does
/// the HTTP + error mapping.
class UserCrudDataSource {
  const UserCrudDataSource(this._client);

  final DioClient _client;

  // GET /users/{id}  -> wrapped as {"data": {...}}
  Future<UserModel> getUser(int id) async {
    final json = await _client.get('${ApiConstants.users}/$id');
    return UserModel.fromJson((json as Map<String, dynamic>)['data']);
  }

  // POST /users
  Future<CreateUserResponseModel> createUser(CreateUserRequestModel request) async {
    final json = await _client.post(ApiConstants.users, data: request.toJson());
    return CreateUserResponseModel.fromJson(json as Map<String, dynamic>);
  }

  // PUT /users/{id}  (replace whole resource)
  Future<void> updateUser(int id, CreateUserRequestModel request) =>
      _client.put('${ApiConstants.users}/$id', data: request.toJson());

  // PATCH /users/{id}  (send only the changed fields)
  Future<void> patchUser(int id, {String? name, String? job}) =>
      _client.patch('${ApiConstants.users}/$id', data: {'name': ?name, 'job': ?job});

  // DELETE /users/{id}  -> 204 No Content (data is empty)
  Future<void> deleteUser(int id) => _client.delete('${ApiConstants.users}/$id');
}
```

Rules of thumb:
- **Request model → `toJson` only. Response model → `fromJson` (+`toEntity`) only.** Don't write the other direction.
- Repository methods that return nothing return `Future<void>`; the Cubit just emits `Success`.
- **Idempotency:** GET/PUT/DELETE are safe to retry; **POST is not** (retrying can create duplicates). Never auto-retry POST.
- A **PUT** sends the *whole* resource, a **PATCH** only the changed fields (`{'name': ?name}` skips nulls).
- Some APIs wrap data (`{"data": {...}}`): unwrap in the data source/model, never in the Cubit.

---

## SECTION 6 — Complex API response

```json
{
  "page": 1,
  "per_page": 10,
  "total": 100,
  "total_pages": 10,
  "data": [ { "id": 1, "first_name": "George" } ],
  "meta": { "request_id": "abc-123", "sorted_by": "id" }
}
```

```text
JSON ──▶ PagedResponseModel<UserModel> ──toEntity(mapItem)──▶ PagedResult<User> ──▶ Repository ──▶ UseCase ──▶ Cubit
          page, perPage, total,                                  items, page,
          totalPages, data[], meta                               totalPages, hasNext
```

| Class | Layer | Contains | Knows JSON? |
|---|---|---|---|
| `UserModel` | data | `first_name`, `avatar`… (API shape) | ✅ |
| `PagedResponseModel<T>` | data | **Everything** the API returns incl. `perPage`, `total`, raw `meta` | ✅ |
| `User` (entity) | domain | only what screens need | ❌ |
| `PagedResult<T>` | domain | `items`, `page`, `totalPages`, `hasNext` (**not** `perPage`/`total`/`meta`) | ❌ |

**What belongs in the entity?** Only what a screen/rule uses. `perPage` and `request_id` are transport details: they stay in the model and die there. If a screen *does* need `total` ("100 users"), add it to the entity then (YAGNI).

Generic version (verified): use it when the **second** list endpoint appears. For the *first* one, the concrete `UsersResponseModel`/`PagedUsers` from section 4 is faster to type and just as correct:
```dart
import 'package:equatable/equatable.dart';

// ---------- domain (feature-agnostic, reusable for every list endpoint)
class PagedResult<T> extends Equatable {
  const PagedResult({required this.items, required this.page, required this.totalPages});

  final List<T> items;
  final int page;
  final int totalPages;

  bool get hasNext => page < totalPages;

  @override
  List<Object?> get props => [items, page, totalPages];
}

// ---------- data
class PagedResponseModel<T> {
  const PagedResponseModel({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.data,
    this.meta,
  });

  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final List<T> data;
  final Map<String, dynamic>? meta; // keep raw until you actually need it

  factory PagedResponseModel.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) => PagedResponseModel(
    page: json['page'] as int,
    perPage: json['per_page'] as int,
    total: json['total'] as int,
    totalPages: json['total_pages'] as int,
    data: (json['data'] as List).map((e) => fromItem(e as Map<String, dynamic>)).toList(),
    meta: json['meta'] as Map<String, dynamic>?,
  );

  /// Item mapping (Model -> Entity) is passed in, so this class stays generic.
  PagedResult<E> toEntity<E>(E Function(T model) mapItem) =>
      PagedResult(items: data.map(mapItem).toList(), page: page, totalPages: totalPages);
}

// ---------- usage inside a data source + repository
// final model = PagedResponseModel.fromJson(json, UserModel.fromJson);
// return model.toEntity((m) => m.toEntity());
```

**Defensive parsing cheat sheet**

| Situation | Code | Rule |
|---|---|---|
| Required field | `json['id'] as int` | Strict: a wrong contract should fail loudly (`TypeError` → `ParsingFailure`) |
| Optional field | `json['bio'] as String?` | Nullable in the model *and* decide the entity default in `toEntity()` |
| Missing list | `(json['tags'] as List?) ?? const []` | Default only where the API contract allows absence |
| Number could be int or double | `(json['price'] as num).toDouble()` | JSON has one number type |
| Dates | `DateTime.parse(json['createdAt'] as String)` (`tryParse` if optional) | Convert in the model, never in the UI |
| `id` sometimes string | `int.parse('${json['id']}')` | Normalize at the boundary |
| snake_case → camelCase | `firstName: json['first_name']` | Naming conversion is a model concern |
| Nested object | `AddressModel.fromJson(json['address'] as Map<String, dynamic>)` | One model per object |
| Unknown enum value | `Status.values.asNameMap()[v] ?? Status.unknown` | Never `byName` on server data |

**Anti-pattern:** `json['id'] ?? 0`, `?? ''`. It converts a broken API into a valid-looking blank row. Fail loudly or model the field as nullable on purpose.

---

## SECTION 7 — Pagination

```text
Page 1 ──▶ user scrolls to the end ──▶ Page 2 ──▶ APPEND ──▶ end again ──▶ Page 3 ──▶ APPEND ──▶ … ──▶ page == totalPages ──▶ stop
 (full-screen loader)              (footer loader, list stays)
```

### State fields

| Field | Type | Meaning |
|---|---|---|
| `users` | `List<User>` | Everything loaded so far (**append, never replace**) |
| `currentPage` | `int` | Last page successfully loaded (next request = `currentPage + 1`) |
| `totalPages` | `int` | From the API envelope (`total_pages`) |
| `isLoadingMore` | `bool` | A next-page request is in flight (footer shows a spinner) |
| `hasReachedMax` | `bool` getter | `currentPage >= totalPages`: stop asking |
| `loadMoreFailed` | `bool` | Page N+1 failed; keep the list, show *Retry* in the footer |

(LITE stores `hasNext` instead of `totalPages`/`hasReachedMax`. Same idea, one field less.)

### Initial loading vs pagination loading

| | Initial loading | Pagination loading |
|---|---|---|
| State | `UserLoading` (a **separate state**) | `UserLoaded(isLoadingMore: true)` (**same state**, flag flipped) |
| Data on screen | none | the whole list stays |
| UI | Full-screen spinner | Spinner as the **last list item** |
| On failure | `UserError` + Retry button (full screen) | List stays; footer shows *"Failed to load. Tap to retry"* |
| Why | Nothing to show yet | Replacing the list with a spinner makes the scroll position jump and loses context |

### The three guards in `loadMore()` (this is the whole trick)

```dart
if (current is! UserLoaded ||      // not loaded yet / error → nothing to append to
    current.isLoadingMore ||       // a request is already running → ignore duplicate scroll events
    current.hasReachedMax) {       // no more pages
  return;
}
```
The UI may call it 100 times; the Cubit lets exactly one through. In **Bloc**, the same guarantee is one line: `on<NextPage>(_onNextPage, transformer: droppable())`.

Also: `if (isClosed) return;` after every `await` (user left the screen), and `emit(current.copyWith(...))` (never rebuild the object by hand: you will forget a field).

**Stale responses.** `_generation` is bumped by every fresh `fetchUsers()`. A `loadMore` (or an older `fetchUsers`) that finishes after a newer reload compares generations and **drops its result**, otherwise page 2 of the *old* list would be appended to the *new* one. Tested with `Completer`s in `user_cubit_test.dart`.

### Two ways to trigger "load more"

| | Footer trigger (**used in this guide**) | `ScrollController` threshold |
|---|---|---|
| How | Last list item's `initState` / `itemBuilder` asks for the next page | Listener checks `pixels >= maxScrollExtent - 200` |
| Short first page (6 items on a tall phone) | ✅ Works (footer is visible, so it loads) | ❌ **Nothing to scroll → never loads page 2** |
| Typing | ~8 lines | ~15 lines + `dispose` |
| Familiarity to interviewers | Medium | High: be able to write it |

ScrollController alternative (verified):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../feature/user/presentation/cubit/user_cubit.dart';

/// ALTERNATIVE to the footer trigger: classic ScrollController threshold.
/// Weakness: if page 1 does not fill the screen there is nothing to scroll,
/// so page 2 is never requested.
class UserListWithController extends StatefulWidget {
  const UserListWithController({super.key});

  @override
  State<UserListWithController> createState() => _UserListWithControllerState();
}

class _UserListWithControllerState extends State<UserListWithController> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final nearBottom = _controller.position.pixels >= _controller.position.maxScrollExtent - 200;
      if (nearBottom) context.read<UserCubit>().loadMore(); // Cubit ignores duplicates
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListView.builder(controller: _controller, itemBuilder: (_, i) => Text('$i'));
}
```

### Pull-to-refresh
`RefreshIndicator(onRefresh: () => cubit.fetchUsers(), …)`. In the FULL Cubit `fetchUsers()` emits `UserLoading`, which swaps the list for a spinner mid-pull. For a polished refresh, add a `refresh()` that *doesn't* emit `UserLoading` and replaces the list on success. Mention it; don't build it unless asked.

### Pagination types (know the vocabulary)
| Type | Request | Pros / cons |
|---|---|---|
| **Page-number** (`?page=2`) (reqres) | page index | Simple; unstable if items are inserted while paging |
| **Offset/limit** (`?offset=20&limit=20`) | skip N | Same instability |
| **Cursor** (`?after=<token>`) | opaque token from last response | Stable and scales; store `nextCursor` instead of `currentPage` |

---

## SECTION 8 — Search

```text
User types ──▶ TextField.onChanged ──▶ DEBOUNCE (wait 400 ms of silence) ──▶ Cubit.fetchUsers(query)
                                                                                   │
              UI ◀── state ◀── Cubit (ignores STALE responses) ◀── API `GET /users?q=…`
```

### Client-side vs server-side

| | Client-side | Server-side |
|---|---|---|
| Use when | The **complete** dataset is already loaded (≤ a few hundred rows, no pagination) | Data is paginated / large / changes on the server |
| Cost | Zero network, instant | One request per (debounced) change |
| Debounce needed? | No | **Yes**, otherwise one request per keystroke |
| Correctness trap | With pagination it only searches the *loaded pages* → misleading | Race conditions: slow old response overwrites newer one |
| Where | Widget / Cubit filters `state.users` | Repository → DataSource sends `?q=` |

**Client-side (verified), no Cubit/API change:**
```dart
import 'package:flutter/material.dart';

import '../feature/user/domain/entity/user.dart';
import '../feature/user/presentation/widgets/user_tile.dart';

/// CLIENT-SIDE search: the full list is already in memory -> filter it.
/// No API call, no debounce needed, no Cubit change.
class FilteredUserList extends StatefulWidget {
  const FilteredUserList({super.key, required this.users});

  final List<User> users;

  @override
  State<FilteredUserList> createState() => _FilteredUserListState();
}

class _FilteredUserListState extends State<FilteredUserList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final visible = widget.users
        .where((u) => u.fullName.toLowerCase().contains(q) || u.email.toLowerCase().contains(q))
        .toList();

    return Column(
      children: [
        TextField(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (_, i) => UserTile(user: visible[i]),
          ),
        ),
      ],
    );
  }
}
```

### Server-side, exactly which lines change (verified)

`reqres` has no `q` param, so the request works but the filter is ignored; the plumbing is what you'd show. Changes, **bottom to top**:

| File | Change |
|---|---|
| `user_remote_data_source.dart` | `getUsers({required int page, String query = ''})` |
| `user_remote_data_source_impl.dart` | `query: {'page': page, if (query.isNotEmpty) 'q': query}` |
| `user_repository.dart` / `_impl.dart` / `get_users.dart` | add `String query = ''`, pass it down |
| `user_cubit.dart` | store `_query`; `fetchUsers({String? query})`; pass `query` in `loadMore`; **drop stale responses** (below) |
| `user_search_field.dart` + `user_page.dart` | `TextField` with `Debouncer`, placed **outside** the `BlocBuilder` |

**`core/utils/debouncer.dart`**
```dart
import 'dart:async';

/// Runs only the LAST call after [delay] of silence (typing -> one API call).
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}
```

**`user_cubit.dart`** with search + stale-response protection
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/usecase/get_users.dart';
import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  UserCubit(this._getUsers) : super(const UserInitial());

  final GetUsers _getUsers;
  String _query = '';

  /// First page. Pass [query] to search; omit it to reuse the current query
  /// (that is what the Retry button does).
  Future<void> fetchUsers({String? query}) async {
    _query = query?.trim() ?? _query;
    final requested = _query;
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1, query: requested);
      if (isClosed || requested != _query) return; // stale: user typed again
      emit(
        UserLoaded(
          users: result.users,
          currentPage: result.page,
          totalPages: result.totalPages,
        ),
      );
    } on Failure catch (failure) {
      if (isClosed || requested != _query) return;
      emit(UserError(failure.message));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! UserLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }

    final requested = _query;
    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final result = await _getUsers(
        page: current.currentPage + 1,
        query: requested,
      );
      if (isClosed || requested != _query) return;
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          currentPage: result.page,
          totalPages: result.totalPages,
          isLoadingMore: false,
        ),
      );
    } on Failure {
      if (isClosed || requested != _query) return;
      emit(current.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }
}
```

**`widgets/user_search_field.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/debouncer.dart';
import '../cubit/user_cubit.dart';

class UserSearchField extends StatefulWidget {
  const UserSearchField({super.key});

  @override
  State<UserSearchField> createState() => _UserSearchFieldState();
}

class _UserSearchFieldState extends State<UserSearchField> {
  final _debouncer = Debouncer(const Duration(milliseconds: 400));

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: TextField(
      decoration: const InputDecoration(
        hintText: 'Search users',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
      ),
      onChanged: (value) => _debouncer.run(
        () => context.read<UserCubit>().fetchUsers(query: value),
      ),
    ),
  );
}
```

**`pages/user_page.dart`**: search field sits *outside* `BlocBuilder` so it keeps focus while the list shows a spinner.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/user_cubit.dart';
import '../cubit/user_state.dart';
import '../widgets/error_view.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/user_search_field.dart';
import '../widgets/user_tile.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Users')),
    body: Column(
      children: [
        const UserSearchField(), // outside BlocBuilder: keeps focus while loading
        Expanded(
          child: BlocBuilder<UserCubit, UserState>(
            builder: (context, state) => switch (state) {
              UserInitial() ||
              UserLoading() => const Center(child: CircularProgressIndicator()),
              UserError(:final message) => ErrorView(
                message: message,
                onRetry: context.read<UserCubit>().fetchUsers,
              ),
              UserLoaded() => _UserList(state: state),
            },
          ),
        ),
      ],
    ),
  );
}

class _UserList extends StatelessWidget {
  const _UserList({required this.state});

  final UserLoaded state;

  @override
  Widget build(BuildContext context) {
    final count = state.users.length;
    return ListView.builder(
      itemCount: state.hasReachedMax ? count : count + 1, // +1 = footer
      itemBuilder: (_, index) => index < count
          ? UserTile(user: state.users[index])
          : LoadMoreFooter(failed: state.loadMoreFailed),
    );
  }
}
```

**The stale-response race (say this):** user types "ab" (request A, slow) then "abc" (request B, fast). B returns first and renders; then A returns and **overwrites** B with results for "ab". The fix is the `requested != _query` check: each response is only applied if it still matches the current query. In **Bloc**: `on<Search>(…, transformer: restartable())` cancels the previous handler automatically. With Dio you can additionally `CancelToken.cancel()` the old HTTP call (section 20).

---

## SECTION 9 — POST / Login

```text
LoginPage ──▶ LoginCubit ──▶ Login (use case) ──▶ AuthRepository ──▶ AuthRemoteDataSource ──▶ DioClient ──▶ POST /login
 (form)       (Command         (action)           (impl: save token     (request model →          (maps errors)
               state)                              + guard)             JSON, JSON → response)
```

**Request vs response model**

| | Request model | Response model |
|---|---|---|
| Purpose | Shape of the **body we send** | Shape of the **body we receive** |
| Direction | `toJson()` only | `fromJson()` + `toEntity()` only |
| Example | `{ "email": "...", "password": "..." }` | `{ "token": "QpwL5tke4Pnpja7X4" }` |
| Entity | none | `AuthSession(token)` (what the app needs: not the raw envelope) |

Test creds for reqres: `eve.holt@reqres.in` / `cityslicka` → `200 {"token": …}`. A missing password → **`400 {"error":"Missing password"}`**, which flows through `DioClient._bodyMessage` to the snackbar unchanged.

**`domain/entity/auth_session.dart`**
```dart
import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({required this.token});

  final String token;

  @override
  List<Object?> get props => [token];
}
```
**`domain/repository/auth_repository.dart`**
```dart
import '../entity/auth_session.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login({required String email, required String password});
}
```
**`domain/usecase/login.dart`**
```dart
import '../entity/auth_session.dart';
import '../repository/auth_repository.dart';

class Login {
  const Login(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> call({required String email, required String password}) =>
      _repository.login(email: email, password: password);
}
```
**`data/model/login_request_model.dart`** and **`login_response_model.dart`**
```dart
class LoginRequestModel {
  const LoginRequestModel({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}
```
```dart
import '../../domain/entity/auth_session.dart';

class LoginResponseModel {
  const LoginResponseModel({required this.token});

  final String token;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) =>
      LoginResponseModel(token: json['token'] as String);

  AuthSession toEntity() => AuthSession(token: token);
}
```
**`data/data_source/auth_remote_data_source.dart`** (interface + impl together)
```dart
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../model/login_request_model.dart';
import '../model/login_response_model.dart';

// Interface + impl in one file = acceptable interview shortcut.
abstract interface class AuthRemoteDataSource {
  Future<LoginResponseModel> login(LoginRequestModel request);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl(this._client);

  final DioClient _client;

  @override
  Future<LoginResponseModel> login(LoginRequestModel request) async {
    final json = await _client.post(ApiConstants.login, data: request.toJson());
    return LoginResponseModel.fromJson(json as Map<String, dynamic>);
  }
}
```
**`data/repository/auth_repository_impl.dart`**: the repository also persists the token (a *data* concern: the Cubit never sees it).
```dart
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/entity/auth_session.dart';
import '../../domain/repository/auth_repository.dart';
import '../data_source/auth_remote_data_source.dart';
import '../model/login_request_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote, this._tokenStorage);

  final AuthRemoteDataSource _remote;
  final TokenStorage _tokenStorage;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) => guard(() async {
    final response = await _remote.login(
      LoginRequestModel(email: email, password: password),
    );
    await _tokenStorage.save(access: response.token);
    return response.toEntity();
  });
}
```
**`presentation/cubit/login_state.dart`** and **`login_cubit.dart`**: a *Command* state shape.
```dart
import 'package:equatable/equatable.dart';

sealed class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object?> get props => [];
}

class LoginInitial extends LoginState {
  const LoginInitial();
}

class LoginLoading extends LoginState {
  const LoginLoading();
}

class LoginSuccess extends LoginState {
  const LoginSuccess();
}

class LoginError extends LoginState {
  const LoginError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
```
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/report_failure.dart';
import '../../domain/usecase/login.dart';
import 'login_state.dart';

class LoginCubit extends Cubit<LoginState> with FailureReporting<LoginState> {
  LoginCubit(this._login) : super(const LoginInitial());

  final Login _login;

  Future<void> login({required String email, required String password}) async {
    if (state is LoginLoading) return; // ignore double taps
    emit(const LoginLoading());
    try {
      await _login(email: email, password: password);
      if (!isClosed) emit(const LoginSuccess());
    } on Failure catch (failure) {
      reportFailure(failure);
      if (!isClosed) emit(LoginError(failure.message));
    }
  }
}
```
**`presentation/pages/login_page.dart`**: `BlocConsumer`: **listener** = snackbar/navigation, **builder** = button spinner.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/login_cubit.dart';
import '../cubit/login_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Login')),
    body: BlocConsumer<LoginCubit, LoginState>(
      // listener = one-off side effects (snackbar, navigation)
      listener: (context, state) {
        if (state is LoginError) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        } else if (state is LoginSuccess) {
          // The messenger outlives this route, so the snackbar shows on the
          // screen we return to.
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Logged in')));
          Navigator.of(context).pop();
        }
      },
      // builder = what is drawn for the current state
      builder: (context, state) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state is LoginLoading
                  ? null
                  : () => context.read<LoginCubit>().login(
                      email: _email.text.trim(),
                      password: _password.text,
                    ),
              child: state is LoginLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    ),
  );
}
```
**`feature/auth/auth_injection.dart`**: per-feature DI module: registers only this feature's classes. It needs `DioClient` and `TokenStorage` from core, which are registered lazily, so call order doesn't matter.
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

Mounted in `main.dart` as the `/login` route (`BlocProvider(create: (_) => sl<LoginCubit>(), child: const LoginPage())`); the users page opens it from an AppBar icon, and on success the page pops with a *Logged in* snackbar.

Details worth saying: `if (state is LoginLoading) return;` ignores double-taps; passwords are never logged or stored; form validation (non-empty / contains `@`) can live in a use case (section 16) or in the form.

---

## SECTION 10 — Error handling

```text
Dio throws DioException / parsing throws TypeError, FormatException
        │  (DioClient._toException — ONE place)
        ▼
AppException        data layer vocabulary:  ServerException(status) · NetworkException · ParsingException
        │  (guard() in the repository — ONE place)
        ▼
Failure             domain/UI vocabulary:   Unauthorized · Validation · Server · Network · Parsing · Unknown
        │  (Cubit: on Failure catch (f))
        ▼
Error State         UserError(f.message)  →  ErrorView + Retry   /   LoginError → SnackBar
```

| Case | Detected as | `AppException` | `Failure` | User sees |
|---|---|---|---|---|
| **400** | `badResponse` | `ServerException(400)` | `ServerFailure` | server's `error`/`message` or "Bad request." |
| **401** | `badResponse` | `ServerException(401)` | `UnauthorizedFailure` | "Please login again." → refresh flow / go to login |
| **403** | `badResponse` | `ServerException(403)` | `UnauthorizedFailure` | "You do not have access." |
| **404** | `badResponse` | `ServerException(404)` | `ServerFailure` | "Not found." |
| **422** | `badResponse` | `ServerException(422)` | `ValidationFailure` | server's validation message, shown by the form |
| **500+** | `badResponse` | `ServerException(5xx)` | `ServerFailure` | "Server error. Please try later." |
| **Timeout** | `connection/send/receiveTimeout` | `NetworkException` | `NetworkFailure` | "Request timed out. Please try again." |
| **No internet** | `connectionError` | `NetworkException` | `NetworkFailure` | "No internet connection." |
| **Invalid JSON** (not parseable) | `unknown` + `FormatException` (Dio wraps it) | `ParsingException` | `ParsingFailure` | "Unexpected data received from server." |
| **Wrong JSON shape** (null / wrong type) | `TypeError` from `fromJson` | none (caught in `guard`) | `ParsingFailure` | same |
| **Cancelled** | `DioExceptionType.cancel` | `CancelledException` | `CancelledFailure` | nothing: callers ignore it |
| **Anything else** | any other throw | none | `UnknownFailure` | "Something went wrong. Please try again." |

All of this is in `exceptions.dart`, `failures.dart` and `dio_client.dart` (section 4B), tested in `dio_client_test.dart` and `user_repository_impl_test.dart` (section 17).

**Where each conversion happens, and why exactly once:**

| Conversion | Location | Why there |
|---|---|---|
| `DioException` → `AppException` | `DioClient._toException` | Only Dio-aware code touches Dio's types; swap `dio` for `http` and only this file changes |
| `AppException`/`TypeError` → `Failure` | `guard()` used by every repository | One mapping for the whole app, repositories stay 3 lines |
| `Failure` → state/message | Cubit | Cubit decides what the screen shows |

**Rules**
1. **Messages are user-safe.** Never show `e.toString()`, stack traces, or URLs. Log those, show friendly text.
2. The Cubit catches `on Failure`, not `catch (e)`, so real bugs still crash into your error reporter instead of showing "Something went wrong" forever.
3. Show errors where they belong: *Query* → `ErrorView` + Retry. *Command* → SnackBar via `BlocListener`/`BlocConsumer`.
4. **Pagination errors keep the list** (`loadMoreFailed`).
5. A sealed `Failure` lets one exhaustive `switch` decide UI per kind (verified):

```dart
import '../core/errors/failures.dart';

/// Sealed Failure => the compiler forces you to handle every kind.
/// Add a new Failure subclass and this stops compiling until you handle it.
({String title, bool canRetry}) describe(Failure failure) => switch (failure) {
  UnauthorizedFailure() => (title: 'Session expired. Please login.', canRetry: false),
  NetworkFailure() => (title: 'You are offline.', canRetry: true),
  ValidationFailure() => (title: 'Please check your input.', canRetry: false),
  ServerFailure() => (title: 'Server problem. Try later.', canRetry: true),
  CancelledFailure() => (title: '', canRetry: false), // ignored: show nothing
  ParsingFailure() || UnknownFailure() => (title: 'Something went wrong.', canRetry: true),
};
```

6. `UnauthorizedFailure` is special: don't just show text: trigger the refresh (section 13) or logout (section 12).
7. **Nothing is swallowed.** `UnknownFailure`/`ParsingFailure` keep the original `cause` + `stackTrace`; the Cubit calls `reportFailure(failure)` (section 4B) so they reach `Bloc.observer.onError`, while the user only sees the safe message.

---

## SECTION 11 — Dio interceptors

```text
Request ──▶ Interceptor.onRequest ──▶ API ──▶ Interceptor.onResponse ──▶ Response
                 │ add Authorization, headers                │ log, transform
                 ▼                                           ▼
        (error) Interceptor.onError ◀── 4xx/5xx/timeout ── handler.next(err) | handler.resolve(retriedResponse)
```

Three handlers per interceptor, each **must** call exactly one of `handler.next(...)`, `handler.resolve(...)` or `handler.reject(...)`, otherwise the request hangs forever.

| Job | Where | Notes |
|---|---|---|
| **Common headers** (`Accept`, `User-Agent`, app version, locale) | `BaseOptions.headers`, not an interceptor | Static, so no code to run |
| **Authorization token** | `onRequest` of `AuthInterceptor` (section 13) | Reads the token from secure storage per request, so token changes apply immediately |
| **Logging** | A small interceptor, **debug builds only** | `if (kDebugMode) SafeLogInterceptor()` |
| **Refresh token / retry** | `onError` on 401 (section 13) | Use a *separate plain Dio* for the refresh call |
| **Error mapping** | ❌ not an interceptor in this design | Kept in `DioClient`, simpler to explain and test |

Requests pass through interceptors in the order you add them: add `AuthInterceptor` **before** a logger.

**Safe logger (verified): method, URL, status only:**
```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Logs ONLY method, url, status. Never headers (Authorization), never bodies
/// (passwords, tokens, PII). Register it only in debug builds.
class SafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('-> ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    debugPrint('<- ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      'x  ${err.response?.statusCode} ${err.requestOptions.uri} ${err.type.name}',
    );
    handler.next(err);
  }
}
```

### What must NOT be logged in production

| Never log | Why |
|---|---|
| `Authorization` header / access & refresh tokens | Anyone with logs (device, crash reporter, CI) can impersonate the user |
| Request bodies of `/login`, `/register`, `/password` | Passwords |
| Response bodies containing tokens or PII (email, phone, address, health, payment) | Privacy / GDPR / compliance |
| Full bodies at all in release | Size + leak risk + performance |
| Anything under `release` mode | Wrap in `kDebugMode`; Dio's built-in `LogInterceptor` prints headers by default: use `requestHeader: false` or avoid it |

If you must log bodies for debugging, **redact** keys (`password`, `token`, `authorization`) first.

---

## SECTION 12 — Authentication

```text
Login ──▶ Access Token (+ Refresh Token) ──▶ Secure Storage ──▶ Interceptor reads it ──▶ "Authorization: Bearer <access>" on every request
```

| | Access token | Refresh token |
|---|---|---|
| Lifetime | Short (minutes to ~1 h) | Long (days–weeks) |
| Sent with | **Every** API request | **Only** to the refresh endpoint |
| If stolen | Limited damage window | Serious: can mint new access tokens |
| Storage | Secure storage (or memory) | **Secure storage only** |
| Revocable | Expires by itself | Server can revoke (logout/rotation) |

**Where it lives:** Keychain (iOS) / Keystore (Android) via `flutter_secure_storage`. **Never** `SharedPreferences` or a file: those are plain text.

**`core/storage/token_storage.dart`** (verified)
```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain (iOS) / Keystore (Android). Never SharedPreferences for tokens.
class TokenStorage {
  const TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  Future<String?> readAccess() => _read(_accessKey);
  Future<String?> readRefresh() => _read(_refreshKey);

  /// Keychain unavailable (e.g. missing entitlement) = "not logged in",
  /// never a crash inside every request.
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return null;
    }
  }

  Future<void> save({required String access, String? refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
```

**The rules**
1. **Only the interceptor attaches the token.** Repositories, Cubits and widgets never touch it.
2. The **repository** saves the token after login (a data concern), as in `AuthRepositoryImpl`.
3. **App start:** read the token; present → go Home, absent → Login (a tiny `AuthCubit`/splash decides).
4. **Logout:** `storage.clear()` + reset in-memory state (and any caches) + navigate to Login. Also call the server's logout/revoke endpoint if it exists.
5. **Session expired** (refresh failed): interceptor clears storage and lets the `UnauthorizedFailure` through; one app-level listener (e.g. `BlocListener<AuthCubit>`) navigates to Login. Avoid navigating from inside repositories.
6. 401 means *unauthenticated* (token missing/expired); 403 means *authenticated but not allowed*. Only 401 triggers refresh.

---

## SECTION 13 — Retry & Refresh token

```text
Request ──▶ API ──▶ 401 ──▶ Refresh Token ──▶ New Access Token ──▶ Retry Original Request ──▶ Success
                                 │ fails?
                                 ▼
                      clear storage ──▶ UnauthorizedFailure ──▶ Login screen
```

### The 20-minute version (say it; code only if asked, ≈12 lines, verified)
```dart
import 'package:dio/dio.dart';

import '../core/storage/token_storage.dart';

/// 12-line interview version: 401 -> refresh -> retry once. No parallel-request
/// handling (mention it verbally: "in production I'd share one refresh Future").
class LiteRefreshInterceptor extends Interceptor {
  LiteRefreshInterceptor(this.storage, this.plainDio);

  final TokenStorage storage;
  final Dio plainDio; // Dio WITHOUT this interceptor

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) return handler.next(err);
    try {
      final res = await plainDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': await storage.readRefresh()},
      );
      final access = res.data!['access_token'] as String;
      await storage.save(access: access);
      final retry = err.requestOptions..headers['Authorization'] = 'Bearer $access';
      handler.resolve(await plainDio.fetch<dynamic>(retry));
    } catch (_) {
      handler.next(err);
    }
  }
}
```
Then say: *"In production I also de-duplicate parallel refreshes."*

### The production version (verified)
```dart
import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// 1. onRequest: attach the `Authorization: Bearer` header.
/// 2. onError 401: refresh once, retry the original request with the new token.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.storage, required this.plainDio});

  final TokenStorage storage;

  /// Dio WITHOUT this interceptor (same baseUrl) - used for refresh + retry,
  /// so a failing refresh can never trigger another refresh (infinite loop).
  final Dio plainDio;

  Future<String?>? _refreshing; // all parallel 401s share ONE refresh call

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await storage.readAccess();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) return handler.next(err);

    final newToken = await (_refreshing ??= _refresh().whenComplete(
      () => _refreshing = null,
    ));
    if (newToken == null) return handler.next(err); // refresh failed -> logout

    try {
      final retry = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken';
      handler.resolve(await plainDio.fetch<dynamic>(retry));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<String?> _refresh() async {
    final refreshToken = await storage.readRefresh();
    if (refreshToken == null) return null;
    try {
      final response = await plainDio.post<Map<String, dynamic>>(
        '/auth/refresh', // your backend's refresh endpoint
        data: {'refresh_token': refreshToken},
      );
      final access = response.data!['access_token'] as String;
      await storage.save(
        access: access,
        refresh: response.data!['refresh_token'] as String?,
      );
      return access;
    } catch (_) {
      await storage.clear(); // refresh token dead -> user must login again
      return null;
    }
  }
}
```

`createDio()` in `core/di/injection.dart` (section 4B) attaches it when Dio is built, so there is no ordering to get wrong. Reqres has no refresh endpoint; `/auth/refresh` is the template you'd point at your backend, and the fake-HTTP tests in section 17 prove the flow.

### The four pitfalls this code avoids (they *will* ask)

| Pitfall | Symptom | Fix used above |
|---|---|---|
| Refresh call goes through the same interceptor | 401 on `/refresh` triggers another refresh → **infinite loop** | `plainDio` (same `baseUrl`, **no** auth interceptor) for refresh *and* the retry |
| `QueuedInterceptor` + retrying on the **same** Dio | **Deadlock**: the retry waits in the queue behind the handler that is waiting for the retry | Plain `Interceptor` + `plainDio` for retry |
| 5 screens fire 5 requests, all get 401 | 5 refresh calls; with refresh-token rotation, 4 of them **invalidate each other** | `_refreshing ??=` shares **one** in-flight refresh `Future` |
| Retry forever | Endless loop on a truly invalid session | Retry **once** (the retry uses `plainDio`, so it can't re-enter the interceptor); failed refresh → `storage.clear()` |

### Retry for flaky networks (different from 401 refresh)
Retry **idempotent reads only** (GET), **only** network failures (not 4xx), with backoff. Never auto-retry POST. Verified helper:
```dart
import '../core/errors/exceptions.dart';

/// Retry ONLY idempotent calls (GET). Never blindly retry POST (double charge!).
/// Retries network problems, not 4xx (the same request will fail the same way).
Future<T> retry<T>(Future<T> Function() action, {int maxAttempts = 3}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } on NetworkException {
      if (attempt >= maxAttempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 300 * attempt)); // backoff
    }
  }
}

// In the data source:
//   final json = await retry(() => _client.get(ApiConstants.users, query: {...}));
```

---

## SECTION 14 — Cubit vs BLoC

| | **Cubit** | **BLoC** |
|---|---|---|
| Input | **Methods**: `cubit.loadMore()` | **Events**: `bloc.add(UsersNextPageRequested())` |
| Mental model | "Call a function, state changes" | "Something *happened*; map it to state" |
| Boilerplate | Less (no event classes) | More (event sealed class + `on<E>` handlers) |
| Traceability | You see state transitions | You see **event → state** transitions (`onTransition`, great for logging/analytics/replay) |
| Concurrency control | Manual guards (`if (isLoadingMore) return`) | **Transformers**: `droppable()`, `restartable()`, `sequential()`, `debounce` (via `bloc_concurrency` / `stream_transform`) |
| Live-coding speed | **Faster** | Slower (~+25% typing) |
| Explain-ability | Simplest | Needs a sentence on events |

### When to choose Cubit
Request/response screens: lists, details, login, forms, settings. One action ≈ one method. *Examples:* user list with pagination, login, profile, toggling a favorite.

### When to choose BLoC
- **Many overlapping triggers** that must be coordinated (search typing + filters + pagination + pull-to-refresh) → `restartable()` for search, `droppable()` for scroll.
- You need an **event log** (analytics, undo/redo, debugging "what sequence led here?").
- **Streams as input**: websocket messages, location updates, debounced text events.
- The interviewer says "use Bloc".
*Examples:* chat (messages in + typing + presence events), search-as-you-type with filters, cart with undo, checkout wizard.

**Interview line:** *"I'll start with Cubit for speed and clarity; if concurrency between triggers becomes the problem, that's exactly what Bloc's event transformers solve, and the state, use case, and UI barely change."*

### Same feature as a BLoC (verified)
Same `UserState`, same `GetUsers`; only the input changes and the manual guard becomes a transformer:
```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/errors/failures.dart';
import '../feature/user/domain/usecase/get_users.dart';
import '../feature/user/presentation/cubit/user_state.dart';

// ---------- events: WHAT HAPPENED (not what to do)
sealed class UserEvent extends Equatable {
  const UserEvent();

  @override
  List<Object?> get props => [];
}

class UsersStarted extends UserEvent {
  const UsersStarted();
}

class UsersNextPageRequested extends UserEvent {
  const UsersNextPageRequested();
}

// ---------- same states, same use case as the Cubit version
class UserBloc extends Bloc<UserEvent, UserState> {
  UserBloc(this._getUsers) : super(const UserInitial()) {
    on<UsersStarted>(_onStarted, transformer: restartable());
    // droppable(): ignore taps/scroll events while one is already running.
    // This replaces the manual `if (isLoadingMore) return;` guard.
    on<UsersNextPageRequested>(_onNextPage, transformer: droppable());
  }

  final GetUsers _getUsers;

  Future<void> _onStarted(UsersStarted event, Emitter<UserState> emit) async {
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1);
      emit(
        UserLoaded(users: result.users, currentPage: result.page, totalPages: result.totalPages),
      );
    } on Failure catch (failure) {
      emit(UserError(failure.message));
    }
  }

  Future<void> _onNextPage(UsersNextPageRequested event, Emitter<UserState> emit) async {
    final current = state;
    if (current is! UserLoaded || current.hasReachedMax) return;

    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final result = await _getUsers(page: current.currentPage + 1);
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          currentPage: result.page,
          totalPages: result.totalPages,
          isLoadingMore: false,
        ),
      );
    } on Failure {
      emit(current.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }
}
// UI:  context.read<UserBloc>().add(const UsersNextPageRequested());
```
Provide with `BlocProvider(create: (_) => UserBloc(GetUsers(repository))..add(const UsersStarted()))`; `BlocBuilder<UserBloc, UserState>` is unchanged.

---

## SECTION 15 — Model vs Entity

```text
JSON ──▶ UserModel ──toEntity()──▶ User
 data ░░░ data ░░░░░░░░░░░░░░░░░░░ domain
```

**Why API DTOs must not leak into the domain/UI:**
1. **The backend is not yours.** It renames `first_name`→`given_name`, adds fields, makes one nullable. With a mapper, one file changes; without it, every widget, Cubit and test changes.
2. **Different shapes serve different needs.** Model: `first_name`, `avatar`, `per_page`, `meta`. Entity: `fullName`, maybe a computed `isAdmin`.
3. **The domain must stay pure Dart** so it is trivially testable and portable (no `fromJson`, no `json_annotation`).
4. **Versioning**: API v1 and v2 can have different models mapping to the **same** entity.

| | `UserModel extends User` | `UserModel` → `toEntity()` → `User` |
|---|---|---|
| Speed in a 20-min interview | **Fastest** (`super.id`, no mapper) | +6–8 lines per model (≈ 30 s) |
| Domain purity | Entity inherits from nothing, but models *are* entities, so the shape coupling is permanent | ✅ Clean: entity has no idea JSON exists |
| Extra API fields (`perPage`, `meta`) | Forced into the entity or lost | Stay in the model |
| Backend renames a field | Ripples through the app | Mapper only |
| Wrapper/envelope types | Tempts you to put them in `data/` and import upward (what happened in the audit) | Natural: wrapper model → wrapper entity |
| **Verdict** | Acceptable *only if* you say "shortcut for time" **and** the entity still lives in `domain/` with no JSON code | **Default. Use it in the interview and production.** |

Fast-but-honest version, if truly out of time:
```dart
class UserModel extends User {                       // shortcut for time;
  const UserModel({required super.id, required super.email /* … */});
  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(id: j['id'] as int, email: j['email'] as String /* … */);
}                                                    // production: toEntity()
```

---

## SECTION 16 — UseCase

| Use case | Wraps | Earns its place? |
|---|---|---|
| `GetUsers(page)` | `repository.getUsers` | Thin. Keep as the layering seam. |
| `GetUserDetails(id)` | `repository.getUser` | Thin. |
| `Login(email, password)` | `authRepository.login` | Becomes **useful** the day you add validation, analytics, or "save token + fetch profile". |
| `CreateUser`, `UpdateUser`, `DeleteUser` | repository writes | Thin; useful with rules ("can't delete yourself"). |
| `PlaceOrder` | `cartRepo` + `stockRepo` + `paymentRepo` | **Very** useful: orchestrates several repositories and rules. |

**Useful when**
- It **owns a business rule** (validation, permissions, pricing, ordering of steps).
- It **combines multiple repositories** (`GetUserWithPosts`).
- You want one **named, mockable seam** per business action (clear Cubit tests).
- Several screens/Cubits reuse the same action.

**Over-engineering when**
- Every repository method gets a pass-through use case on a tiny app (**25 files for CRUD**).
- A "use case" that just renames the repository method and adds nothing.
- A generic `UseCase<Type, Params>` base class + `NoParams` + `Either` on a 20-min task.

**Interview stance:** *"For a simple read I'd be fine calling the repository from the Cubit. Here I included a use case because it's the seam where rules live, and it keeps the Cubit ignorant of data sources. It's one small file."* Include it; interviewers expect the layer, and you show judgment by naming the trade-off.

A use case that **earns its place** (verified): validation is a business rule, not UI code and not data code.
```dart
import '../core/errors/failures.dart';
import '../feature/auth/domain/entity/auth_session.dart';
import '../feature/auth/domain/repository/auth_repository.dart';

/// A use case that earns its place: it owns a BUSINESS RULE (validation),
/// not just a pass-through.
class LoginWithValidation {
  const LoginWithValidation(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> call({required String email, required String password}) {
    if (!email.contains('@')) throw const ValidationFailure('Enter a valid email.');
    if (password.length < 6) {
      throw const ValidationFailure('Password must be at least 6 characters.');
    }
    return _repository.login(email: email, password: password);
  }
}
```
The Cubit already handles it: `ValidationFailure` is a `Failure`, so `on Failure catch` shows the message.

---

## SECTION 17 — Testing

| Layer | Test | Mock | Verifies |
|---|---|---|---|
| **Widget** | `UserPage` | Fake `UserRepository` (the interface makes this 10 lines) | Loader → list; error → Retry → list; pagination appends |
| **Cubit** | `bloc_test` | `GetUsers` (mocktail) | Exact state sequences: success, failure, `loadMore` append, last page, page-2 failure |
| **UseCase** | plain test | `UserRepository` | Rules (validation) / delegation |
| **Repository** | plain test | `UserRemoteDataSource` | Model→Entity mapping; each Exception → right Failure |
| **DataSource** | plain test | `DioClient` | Correct path/query; JSON parsed into model |
| **DioClient** | plain test | `Dio` | Status/timeout/invalid JSON/cancel → right `AppException`; server message extracted; all 5 verbs |
| **Interceptor** | plain test | **fake HTTP adapter** (scripted responses) + mocked `TokenStorage` | Bearer header; 401 → refresh → retry; parallel 401s share ONE refresh; failed refresh clears storage; no loop |
| **Token storage** | plain test | `FlutterSecureStorage` | Reads/writes the right keys; unavailable keychain = not logged in |
| **DI graph** | plain test | none | Whole graph resolves; Cubits are factories; Dio has baseUrl, timeouts, auth interceptor |
| **Safe logger** | plain test | fake adapter + captured `debugPrint` | Logs method/url/status only: never tokens, passwords, bodies |

What **not** to test: Dio itself, `fromJson` of trivial models one-by-one, private methods. Test behaviour at the boundaries.

Run: `flutter test`. (All of the following are from the verified suite.)

### Success + Failure + Pagination: the Cubit
```dart
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
```
Note: `seed:` starts the Cubit in a given state (page 1 loaded) so the pagination case is a 4-line test. States compare with `==` **because they are `Equatable`**: that is the practical payoff.

### Repository: exceptions → failures, model → entity
```dart
import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/user/data/data_source/user_remote_data_source.dart';
import 'package:demoapi/feature/user/data/model/user_model.dart';
import 'package:demoapi/feature/user/data/model/users_response_model.dart';
import 'package:demoapi/feature/user/data/repository/user_repository_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

class MockRemote extends Mock implements UserRemoteDataSource {}

void main() {
  late MockRemote remote;
  late UserRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    repository = UserRepositoryImpl(remote);
  });

  test('maps model -> entity on success', () async {
    when(() => remote.getUsers(page: 1)).thenAnswer(
      (_) async => const UsersResponseModel(
        page: 1,
        perPage: 6,
        total: 12,
        totalPages: 2,
        data: [
          UserModel(
            id: 1,
            email: 'a@a.com',
            firstName: 'A',
            lastName: 'One',
            avatar: '',
          ),
        ],
      ),
    );

    final result = await repository.getUsers(page: 1);

    expect(result.users.single.fullName, 'A One');
    expect(result.hasNext, isTrue);
  });

  test('ServerException(404) -> ServerFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const ServerException('Not found.', statusCode: 404));

    expect(repository.getUsers(page: 1), throwsA(isA<ServerFailure>()));
  });

  test('ServerException(401) -> UnauthorizedFailure', () {
    when(
      () => remote.getUsers(page: 1),
    ).thenThrow(const ServerException('Please login again.', statusCode: 401));

    expect(repository.getUsers(page: 1), throwsA(isA<UnauthorizedFailure>()));
  });

  test('ServerException(422) -> ValidationFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const ServerException('Email is invalid.', statusCode: 422));

    expect(repository.getUsers(page: 1), throwsA(isA<ValidationFailure>()));
  });

  test('NetworkException -> NetworkFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const NetworkException('No internet connection.'));

    expect(repository.getUsers(page: 1), throwsA(isA<NetworkFailure>()));
  });

  test('bad JSON shape (TypeError) -> ParsingFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenAnswer((_) async => UsersResponseModel.fromJson({'page': 'oops'}));

    expect(repository.getUsers(page: 1), throwsA(isA<ParsingFailure>()));
  });

  test('CancelledException -> CancelledFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const CancelledException('Request cancelled.'));

    expect(repository.getUsers(page: 1), throwsA(isA<CancelledFailure>()));
  });

  test('ParsingFailure keeps the technical cause for logging', () async {
    when(() => remote.getUsers(page: 1))
        .thenAnswer((_) async => UsersResponseModel.fromJson({'page': 'oops'}));

    await expectLater(
      repository.getUsers(page: 1),
      throwsA(
        isA<ParsingFailure>()
            .having((f) => f.cause, 'cause', isA<TypeError>())
            .having((f) => f.stackTrace, 'stackTrace', isNotNull)
            .having(
              (f) => f.message,
              'user-safe message',
              isNot(contains('type')),
            ),
      ),
    );
  });

  test('unknown errors become UnknownFailure and keep cause + stack', () async {
    when(() => remote.getUsers(page: 1)).thenThrow(StateError('boom'));

    await expectLater(
      repository.getUsers(page: 1),
      throwsA(
        isA<UnknownFailure>()
            .having((f) => f.cause, 'cause', isA<StateError>())
            .having((f) => f.stackTrace, 'stackTrace', isNotNull),
      ),
    );
  });
}
```

### Data source: path, query, parsing
```dart
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
```

### DioClient: HTTP errors → exceptions
```dart
import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DioClient client;

  setUp(() {
    dio = MockDio();
    client = DioClient(dio);
  });

  final options = RequestOptions(path: '/x');
  Response<dynamic> ok(Object? data) =>
      Response(requestOptions: options, data: data);

  DioException badResponse(int code, [Object? body]) => DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: code, data: body),
  );

  void stubGet(Object Function() answer) {
    when(
      () => dio.get<dynamic>(
        '/x',
        queryParameters: any(named: 'queryParameters'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      final a = answer();
      if (a is Exception) throw a;
      return ok(a);
    });
  }

  group('success', () {
    test('GET returns response.data', () async {
      stubGet(() => {'ok': true});
      expect(await client.get('/x'), {'ok': true});
    });

    test('POST / PUT / PATCH / DELETE use the right Dio method', () async {
      when(
        () => dio.post<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('post'));
      when(
        () => dio.put<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('put'));
      when(
        () => dio.patch<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('patch'));
      when(
        () => dio.delete<dynamic>('/x', cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) async => ok(''));

      expect(await client.post('/x', data: {'a': 1}), 'post');
      expect(await client.put('/x', data: {'a': 1}), 'put');
      expect(await client.patch('/x', data: {'a': 1}), 'patch');
      expect(await client.delete('/x'), '');
      verify(() => dio.post<dynamic>('/x', data: {'a': 1})).called(1);
    });

    test('forwards the CancelToken to Dio', () async {
      final token = CancelToken();
      when(
        () => dio.get<dynamic>(
          '/x',
          queryParameters: any(named: 'queryParameters'),
          cancelToken: token,
        ),
      ).thenAnswer((_) async => ok(1));

      await client.get('/x', cancelToken: token);

      verify(
        () => dio.get<dynamic>('/x', queryParameters: null, cancelToken: token),
      ).called(1);
    });
  });

  group('errors', () {
    test('400 {"error": ...} -> ServerException with that message', () {
      stubGet(() => badResponse(400, {'error': 'Missing password'}));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>()
              .having((e) => e.message, 'message', 'Missing password')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('{"message": ...} is understood too', () {
      stubGet(() => badResponse(422, {'message': 'Email is invalid'}));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            'Email is invalid',
          ),
        ),
      );
    });

    test('no body: falls back to a default message per status', () {
      stubGet(() => badResponse(404));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having((e) => e.message, 'm', 'Not found.'),
        ),
      );
    });

    test('5xx -> "Server error" message', () {
      stubGet(() => badResponse(503));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'm',
            contains('Server error'),
          ),
        ),
      );
    });

    test('timeout -> NetworkException', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(client.get('/x'), throwsA(isA<NetworkException>()));
    });

    test('connection error -> NetworkException "No internet"', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      expect(
        client.get('/x'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'm',
            'No internet connection.',
          ),
        ),
      );
    });

    test('cancelled request -> CancelledException (not a network error)', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      );
      expect(client.get('/x'), throwsA(isA<CancelledException>()));
    });

    test('invalid JSON body -> ParsingException (not a network error)', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const FormatException('Unexpected character'),
        ),
      );
      expect(client.get('/x'), throwsA(isA<ParsingException>()));
    });
  });
}
```

### Widget test with a fake repository
```dart
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
```
Gotcha: `ListView` is **lazy**: rows off-screen aren't built, so `find.text('First11 Last')` fails until you `scrollUntilVisible`.

### Login Cubit (Command style)
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/auth/domain/entity/auth_session.dart';
import 'package:demoapi/feature/auth/domain/usecase/login.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_cubit.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLogin extends Mock implements Login {}

void main() {
  late MockLogin login;
  setUp(() => login = MockLogin());

  blocTest<LoginCubit, LoginState>(
    'emits [Loading, Success] when credentials are valid',
    build: () {
      when(() => login(email: 'a@a.com', password: 'secret1'))
          .thenAnswer((_) async => const AuthSession(token: 't'));
      return LoginCubit(login);
    },
    act: (c) => c.login(email: 'a@a.com', password: 'secret1'),
    expect: () => const [LoginLoading(), LoginSuccess()],
  );

  blocTest<LoginCubit, LoginState>(
    'emits [Loading, Error] when the server rejects the login',
    build: () {
      when(
        () => login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const ServerFailure('Missing password', statusCode: 400));
      return LoginCubit(login);
    },
    act: (c) => c.login(email: 'a@a.com', password: ''),
    expect: () => const [LoginLoading(), LoginError('Missing password')],
  );
}
```

### Auth interceptor against a fake HTTP layer
`FakeAdapter` replaces Dio's network layer: the test scripts every response, so the refresh flow is tested without a server.
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Scripted HTTP layer for Dio: no network, the test decides every response.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final ResponseBody Function(RequestOptions) _handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
```
```dart
import 'package:demoapi/core/network/auth_interceptor.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_adapter.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockTokenStorage storage;
  late String access;
  String? refreshToken;
  late int refreshCalls;
  late bool refreshWorks;

  Dio buildDio({int? alwaysStatus}) {
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') {
        refreshCalls++;
        return refreshWorks
            ? json({'access_token': 'new'}, 200)
            : json({'error': 'refresh expired'}, 401);
      }
      if (alwaysStatus != null) {
        return json({'status': alwaysStatus}, alwaysStatus);
      }
      // a "server" that only accepts the NEW token
      return o.headers['Authorization'] == 'Bearer new'
          ? json({'ok': true}, 200)
          : json({'error': 'expired'}, 401);
    });
    final plain = Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = adapter;
    return Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(AuthInterceptor(storage: storage, plainDio: plain));
  }

  setUp(() {
    storage = MockTokenStorage();
    access = 'old';
    refreshToken = 'refresh';
    refreshCalls = 0;
    refreshWorks = true;
    when(() => storage.readAccess()).thenAnswer((_) async => access);
    when(() => storage.readRefresh()).thenAnswer((_) async => refreshToken);
    when(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((i) async => access = i.namedArguments[#access] as String);
    when(() => storage.clear()).thenAnswer((_) async {});
  });

  test('attaches "Authorization: Bearer <token>" to every request', () async {
    final dio = buildDio(alwaysStatus: 200);

    await dio.get<dynamic>('/users');

    final adapter = dio.httpClientAdapter as FakeAdapter;
    expect(adapter.requests.single.headers['Authorization'], 'Bearer old');
  });

  test('no token stored -> no Authorization header', () async {
    when(() => storage.readAccess()).thenAnswer((_) async => null);
    final dio = buildDio(alwaysStatus: 200);

    await dio.get<dynamic>('/users');

    final adapter = dio.httpClientAdapter as FakeAdapter;
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test(
    '401 -> refresh -> retries the original request with the new token',
    () async {
      final dio = buildDio();

      final response = await dio.get<dynamic>('/users');

      expect(response.data, {'ok': true});
      expect(refreshCalls, 1);
      verify(() => storage.save(access: 'new', refresh: null)).called(1);
    },
  );

  test('parallel 401s share ONE refresh call', () async {
    final dio = buildDio();

    final results = await Future.wait([
      dio.get<dynamic>('/a'),
      dio.get<dynamic>('/b'),
      dio.get<dynamic>('/c'),
    ]);

    expect(results.map((r) => r.statusCode), everyElement(200));
    expect(refreshCalls, 1);
  });

  test('refresh fails -> storage cleared, original 401 is surfaced', () async {
    refreshWorks = false;
    final dio = buildDio();

    await expectLater(
      dio.get<dynamic>('/users'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );

    expect(refreshCalls, 1);
    verify(() => storage.clear()).called(1);
  });

  test('no refresh token -> does not call the refresh endpoint', () async {
    refreshToken = null;
    final dio = buildDio();

    await expectLater(dio.get<dynamic>('/users'), throwsA(isA<DioException>()));

    expect(refreshCalls, 0);
  });

  test('non-401 errors pass through untouched (no refresh)', () async {
    final dio = buildDio(alwaysStatus: 500);

    await expectLater(
      dio.get<dynamic>('/users'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          500,
        ),
      ),
    );

    expect(refreshCalls, 0);
  });

  test(
    'retry with the NEW token still 401 -> error surfaced, no refresh loop',
    () async {
      final adapter = FakeAdapter((o) {
        if (o.path == '/auth/refresh') {
          refreshCalls++;
          return json({'access_token': 'new'}, 200);
        }
        return json({
          'error': 'still unauthorized',
        }, 401); // even for the new token
      });
      final plain = Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = adapter;
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(AuthInterceptor(storage: storage, plainDio: plain));

      await expectLater(
        dio.get<dynamic>('/users'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );

      expect(refreshCalls, 1, reason: 'one refresh, not a loop');
    },
  );
}
```

### Token storage, DI graph, safe logger
```dart
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
```
```dart
import 'package:demoapi/core/di/injection.dart';
import 'package:demoapi/core/network/auth_interceptor.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_cubit.dart';
import 'package:demoapi/feature/user/presentation/cubit/user_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
    initDependencies();
  });
  tearDown(() => sl.reset());

  test('the whole graph resolves (catches wiring mistakes at test time)', () {
    expect(sl<UserCubit>(), isA<UserCubit>());
    expect(sl<LoginCubit>(), isA<LoginCubit>());
  });

  test('Cubits are factories: every request gets a NEW instance', () {
    expect(identical(sl<UserCubit>(), sl<UserCubit>()), isFalse);
  });

  test(
    'Dio is a singleton with baseUrl, timeouts and the auth interceptor',
    () {
      final dio = sl<Dio>();

      expect(identical(dio, sl<Dio>()), isTrue);
      expect(dio.options.baseUrl, 'https://reqres.in/api');
      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.interceptors.whereType<AuthInterceptor>(), hasLength(1));
    },
  );

  test('createDio does not need call-order tricks', () {
    final dio = createDio(const TokenStorage(FlutterSecureStorage()));

    expect(dio.interceptors.whereType<AuthInterceptor>(), hasLength(1));
  });
}
```
```dart
import 'package:demoapi/core/network/safe_log_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_adapter.dart';

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  });
  tearDown(() => debugPrint = originalDebugPrint);

  Dio dioReturning(int status) => Dio(BaseOptions(baseUrl: 'http://api.test'))
    ..httpClientAdapter = FakeAdapter(
      (_) => json({'password': 'hunter2', 'token': 'SECRET'}, status),
    )
    ..interceptors.add(SafeLogInterceptor());

  test('logs method, url and status only', () async {
    await dioReturning(200).post<dynamic>(
      '/login',
      data: {'password': 'hunter2'},
      options: Options(headers: {'Authorization': 'Bearer SECRET'}),
    );

    final all = logs.join('\n');
    expect(all, contains('-> POST http://api.test/login'));
    expect(all, contains('<- 200 http://api.test/login'));
  });

  test('NEVER logs tokens, passwords or response bodies', () async {
    await dioReturning(200).post<dynamic>(
      '/login',
      data: {'password': 'hunter2'},
      options: Options(headers: {'Authorization': 'Bearer SECRET'}),
    );

    final all = logs.join('\n');
    expect(all, isNot(contains('SECRET')));
    expect(all, isNot(contains('hunter2')));
    expect(all, isNot(contains('Authorization')));
  });

  test('errors log status and type, still without the body', () async {
    await expectLater(
      dioReturning(500).get<dynamic>('/users'),
      throwsA(isA<DioException>()),
    );

    final all = logs.join('\n');
    expect(all, contains('x  500 http://api.test/users badResponse'));
    expect(all, isNot(contains('SECRET')));
  });
}
```

### Login page, auth repository
```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_cubit.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_state.dart';
import 'package:demoapi/feature/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLoginCubit extends MockCubit<LoginState> implements LoginCubit {}

void main() {
  late MockLoginCubit cubit;

  setUp(() => cubit = MockLoginCubit());

  Widget app({Widget? home}) => MaterialApp(
    home:
        home ??
        BlocProvider<LoginCubit>.value(value: cubit, child: const LoginPage()),
  );

  testWidgets('tapping Login sends the typed email and password', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const LoginInitial());
    when(
      () => cubit.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      ' eve@reqres.in ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'cityslicka',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));

    verify(() => cubit.login(email: 'eve@reqres.in', password: 'cityslicka'))
        .called(1);
  });

  testWidgets('loading disables the button and shows a spinner', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const LoginLoading());

    await tester.pumpWidget(app());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('error shows the server message in a snackbar', (tester) async {
    whenListen(
      cubit,
      Stream.fromIterable(const [
        LoginLoading(),
        LoginError('Missing password'),
      ]),
      initialState: const LoginInitial(),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Missing password'), findsOneWidget);
  });

  testWidgets('success pops back and confirms with a snackbar', (tester) async {
    final controller = StreamController<LoginState>();
    addTearDown(controller.close);
    whenListen(cubit, controller.stream, initialState: const LoginInitial());

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlocProvider<LoginCubit>.value(
                      value: cubit,
                      child: const LoginPage(),
                    ),
                  ),
                ),
                child: const Text('open login'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    controller.add(const LoginSuccess());
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('Logged in'), findsOneWidget);
  });
}
```
```dart
import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:demoapi/feature/auth/data/data_source/auth_remote_data_source.dart';
import 'package:demoapi/feature/auth/data/model/login_request_model.dart';
import 'package:demoapi/feature/auth/data/model/login_response_model.dart';
import 'package:demoapi/feature/auth/data/repository/auth_repository_impl.dart';
import 'package:demoapi/feature/auth/domain/entity/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockRemote remote;
  late MockTokenStorage storage;
  late AuthRepositoryImpl repository;

  setUpAll(
    () =>
        registerFallbackValue(const LoginRequestModel(email: '', password: '')),
  );

  setUp(() {
    remote = MockRemote();
    storage = MockTokenStorage();
    repository = AuthRepositoryImpl(remote, storage);
    when(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async {});
  });

  test(
    'success: sends the request model, stores the token, returns entity',
    () async {
      when(() => remote.login(any()))
          .thenAnswer((_) async => const LoginResponseModel(token: 'abc'));

      final session = await repository.login(
        email: 'a@a.com',
        password: 'secret1',
      );

      expect(session, const AuthSession(token: 'abc'));
      final sent =
          verify(() => remote.login(captureAny())).captured.single
              as LoginRequestModel;
      expect(sent.toJson(), {'email': 'a@a.com', 'password': 'secret1'});
      verify(() => storage.save(access: 'abc', refresh: null)).called(1);
    },
  );

  test('400 -> ServerFailure and NO token is stored', () async {
    when(() => remote.login(any()))
        .thenThrow(const ServerException('Missing password', statusCode: 400));

    await expectLater(
      repository.login(email: 'a@a.com', password: ''),
      throwsA(
        isA<ServerFailure>().having(
          (f) => f.message,
          'message',
          'Missing password',
        ),
      ),
    );
    verifyNever(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    );
  });

  test('offline -> NetworkFailure', () {
    when(() => remote.login(any()))
        .thenThrow(const NetworkException('No internet connection.'));

    expect(
      repository.login(email: 'a@a.com', password: 'x'),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
```

**What to say:** "Because every layer depends on an interface, each test mocks exactly one neighbour. No test touches the network."

---

## SECTION 18 — Interview Cheat Sheet (one page)

### Architecture formula
```text
UI → Cubit → UseCase → Repository(interface) → RepositoryImpl → DataSource → Dio → API
presentation ─▶ domain ◀─ data              (imports point INWARD)
```

### Response formula
```text
API → JSON → Model → toEntity() → Entity → Cubit → State → UI
```

### Error formula
```text
DioException → AppException (DioClient) → Failure (guard in Repository) → Cubit → Error State → Retry
```

### SOLID formula
```text
S = One responsibility        (Cubit = state, Repo = data source choice, Model = JSON)
O = Extend without modifying  (new endpoint = new files + 1 DI line)
L = Substitutable abstraction (Fake/Impl behind the same interface)
I = Small interfaces          (1–3 methods per repository/data source)
D = Depend on abstractions    (Cubit→UseCase→Repository INTERFACE; Impl wired in DI)
```

### Debug formula: when the API integration fails, check bottom → top
```text
API        → hit it with curl/Postman first (is the server returning what you think?)
Dio        → baseUrl/path/query/headers correct? (enable the safe logger) timeout? internet permission/cleartext on Android?
DataSource → response.data runtimeType? does fromJson match the REAL JSON (snake_case, nulls, int vs String)?
Repository → is guard() mapping what you expect? did it throw a Failure?
UseCase    → called with the right arguments?
Cubit      → did it emit? is `on Failure` swallowing a TypeError you should see? isClosed?
UI         → is the right BlocProvider above this widget? does the `switch` handle the state?
```
(Frequent culprits: missing `INTERNET` permission in `AndroidManifest.xml` · `http://` blocked by iOS ATS / Android cleartext · `localhost` instead of `10.0.2.2` on the Android emulator · BlocProvider below the widget that reads it · `as int` on a value that is a `String`.)

### 13-step live-coding order
```text
1 JSON → 2 Entity → 3 Model(+toEntity) → 4 Repo interface → 5 DataSource → 6 RepoImpl
→ 7 UseCase → 8 Cubit → 9 States → 10 UI → 11 DI/main → 12 RUN → 13 pagination/search
```

### Gotcha checklist
- [ ] Interface in **domain**; no `import '…/data/…'` in domain
- [ ] Entities have **no** `fromJson`; models have `toEntity()`
- [ ] Cubit is a **factory**; closed over `isClosed` after `await`
- [ ] `on Failure catch`, user-safe messages, Retry button
- [ ] `loadMore` guarded (state type, `isLoadingMore`, last page)
- [ ] Footer/loader not a full-screen replace on page 2
- [ ] Debounce search; ignore stale responses
- [ ] Never log tokens/bodies in release; token in **secure** storage
- [ ] POST isn't auto-retried

### File budget
| | Files | Lines |
|---|---|---|
| LITE feature (MVP w/o pagination) | 14 | ≈ 270 |
| LITE + pagination | 14 | ≈ 320 |
| FULL (errors, DioClient, widgets, GetIt) | 24 | ≈ 790 |

---

## SECTION 19 — Verbal explanation scripts

### 20-second answer
> "It's Clean Architecture with feature-first folders. The UI talks to a Cubit; the Cubit calls a use case; the use case depends on a repository **interface** in the domain layer; the data layer implements it with Dio and maps JSON models to domain entities. Dependencies point inward, so the domain knows nothing about Dio or Flutter."

### 60-second answer
> "I'm following Clean Architecture with three layers per feature. **Domain** holds entities, the repository interface and use cases: pure Dart, no Flutter, no Dio. **Data** has the JSON models, a remote data source that owns the endpoint and parsing, and a repository implementation that maps models to entities and converts exceptions into failures. **Presentation** has a Cubit with sealed states and the widgets.
> Dependencies point inward: presentation and data both depend on domain, never the other way. That's why the repository interface lives in domain and the implementation in data. The only place that knows the concrete classes is the composition root, so I can swap REST for a cache or a fake in tests without touching the Cubit or UI.
> Errors flow `DioException → AppException → Failure → error state`, so the UI shows a friendly message and a Retry button. Pagination appends pages and ignores duplicate or last-page calls."

### 2-minute detailed answer
> "Let me walk it top to bottom. The **UI** is a stateless page with a `BlocBuilder` that `switch`es over a sealed `UserState`, so the compiler forces me to handle loading, loaded and error. It never fetches; it forwards intent: `fetchUsers`, `loadMore`.
> The **Cubit** holds the screen state. It calls a **use case**, `GetUsers`, which expresses one business action and is the seam where rules would live. The Cubit catches only my typed `Failure`, never a raw exception, and emits an error state with a user-safe message. For pagination it keeps `currentPage`, `totalPages` and `isLoadingMore`, appends new pages, and guards against double calls, loading-in-progress and the last page. If page 2 fails, the list stays and the footer offers a retry.
> The use case depends on the **repository interface**, which I put in the domain layer on purpose: the domain defines what it needs, and the data layer adapts to it, so import arrows point inward. The **repository implementation** calls the remote data source, converts the `UsersResponseModel` into a `PagedUsers` entity via `toEntity()`, and wraps everything in `guard()` which converts exceptions into failures, so Dio types never leave the data layer.
> The **data source** knows the endpoint and the JSON: strict casts so a wrong shape fails loudly instead of rendering blank rows. HTTP goes through a `DioClient` wrapper with all five verbs and a single `DioException → AppException` mapping covering timeouts, no internet, 4xx/5xx with the server's message, and invalid JSON.
> **Dio** is configured once, with base URL, timeouts and interceptors: auth token attached in an interceptor, refresh-on-401 with one shared refresh call, and debug-only logging without headers or bodies.
> Everything is wired in one composition root: manual DI for one feature, GetIt as it grows, with Cubits as factories because `BlocProvider` closes them. Because each layer depends on an interface, tests mock exactly one neighbour: bloc_test for the Cubit, a mocked data source for the repository, and a fake repository for a widget test. SOLID falls out of this: single responsibility per class, open for new endpoints without modification, and dependency inversion at the repository boundary."

### Handling "why did you skip X?"
> "I prioritized a correct, layered, running screen first. X is a hardening step; here's exactly where I'd add it and what it would look like." *(Then point to the file.)*

---

## SECTION 20 — Common interview questions (34, beginner → advanced)

### Beginner

**1. What is Dio?** A powerful Dart HTTP client: interceptors, `BaseOptions`, timeouts, cancellation, form data, multipart, typed errors (`DioException`). I use it over `http` for interceptors (auth/refresh/logging) and consistent error types.

**2. What is a REST API?** An HTTP API organised around **resources** (`/users/7`) with verbs: GET read, POST create, PUT replace, PATCH partial update, DELETE remove; stateless, JSON bodies, meaningful status codes.

**3. What is JSON?** A text format for structured data (objects, arrays, strings, numbers, booleans, null). In Dart it decodes to `Map<String, dynamic>` / `List`; I turn it into typed models with `fromJson`.

**4. What is the Repository pattern?** An abstraction that hides *where* data comes from (REST, cache, DB). The domain asks the repository for entities; the implementation chooses sources, maps models and converts errors.

**5. What is a Cubit?** A lightweight state holder from `flutter_bloc`: methods call `emit(newState)`; the UI rebuilds from the state stream. A Bloc minus events.

**6. What is BLoC?** Business Logic Component: events in, states out, via streams. It adds traceability and event transformers (`droppable`, `restartable`) at the cost of boilerplate.

### Intermediate

**7. Why Clean Architecture?** Testability, replaceable infrastructure (swap Dio/DB without touching business logic), parallel team work per layer, and a place for every concern. Cost: more files; not worth it for a one-screen throwaway.

**8. Why a UseCase?** One named business action, a home for rules and orchestration across repositories, and a mockable seam for Cubit tests. For pure pass-through reads it's optional; I include it for consistency.

**9. Why a Repository interface?** Dependency inversion: domain defines the contract, data implements it. Enables fakes in tests and swapping implementations without touching callers.

**10. Model vs Entity?** Model = API shape (JSON-aware, in data). Entity = business shape (pure, in domain). `toEntity()` is the boundary so backend changes don't ripple.

**11. Where should API calls happen?** Only in the **data layer's remote data source** (through `DioClient`). Never in widgets or Cubits.

**12. How do you handle errors?** `DioException → AppException` in `DioClient`, `AppException/TypeError → Failure` in a repository `guard()`, Cubit catches `on Failure` and emits an error state with a friendly message and Retry. Typed failures let me treat 401, offline and 422 differently.

**13. How do you implement pagination?** State holds list + `currentPage`, `totalPages`, `isLoadingMore`. `loadMore()` guards against wrong state / in-flight / last page, fetches `currentPage+1`, **appends**. Footer shows a spinner or Retry. Initial load is a separate full-screen state.

**14. Why sealed classes for state?** Exhaustive `switch`: add a state and every UI switch fails to compile until handled. No `default:` hiding bugs.

**15. Why `Equatable` on states?** Value equality → no rebuilds for identical emissions and `bloc_test` can compare sequences with `==`.

**16. Why is the Cubit a factory in DI?** `BlocProvider(create:)` closes it on dispose; a singleton would be closed after first use. Stateless things (Dio, repository, use case) are singletons.

**17. GetIt vs manual DI?** Manual composition root for one feature (simplest); GetIt when features multiply, for lazy singletons and test overrides.

**18. Cubit vs Bloc?** Cubit for request/response screens (faster, simpler). Bloc for event-heavy flows needing transformers or an event log.

**19. What does `if (isClosed) return;` do?** After `await`, the user may have left the screen and the Cubit closed; emitting then throws `StateError`. The guard makes it a no-op.

**20. `BlocBuilder` vs `BlocListener` vs `BlocConsumer`?** Builder = draw UI from state. Listener = one-off side effects (snackbar, navigation). Consumer = both. Never navigate from `builder`.

**21. Where do base URL, timeouts and headers go?** `BaseOptions` on the Dio created once at the composition root; paths as constants; auth header in an interceptor.

### Advanced

**22. How do you refresh an expired token?** Interceptor `onError`: on 401, call refresh with a **separate Dio** (no auth interceptor), store the new tokens, retry the original request once with the new header. Share one in-flight refresh `Future` across parallel 401s. If refresh fails → clear storage, surface `UnauthorizedFailure`, go to login.

**23. How do you retry failed requests?** Only **idempotent** calls (GET) and only for **network** failures, with exponential backoff and a max attempt count. Never auto-retry POST (duplicates). A small `retry()` helper around the data-source call or a retry interceptor.

**24. How do you prevent duplicate pagination calls?** Guard in the Cubit (`isLoadingMore`, last page, state type). In Bloc: `droppable()` transformer. UI can fire as often as it likes.

**25. How do you cancel API requests?** Dio `CancelToken`: keep one per search/screen, `cancel()` on new input or `close()`. Dio throws `DioException(type: cancel)`, which I map to a "cancelled" outcome that the UI ignores. In Bloc, `restartable()` cancels the previous handler.

**26. How do you handle concurrent requests?** Independent calls: `Future.wait` (or Dart 3 records `(await (a, b).wait)`) for parallel loading; combine in a use case. Dependent calls: sequential. Guard against races on one resource: ignore stale responses (compare request id/query), `droppable`/`restartable`, de-dupe in-flight futures.

**27. How do you cache API responses?** A repository **decorator**: `CachedUserRepository(UserRepositoryImpl)` with TTL (in-memory map) so UI/use case don't change (verified code below). For persistence use a DB/`hive`/`drift`; for HTTP semantics honour `ETag`/`Cache-Control` (`dio_cache_interceptor`). Invalidate on mutations. Strategy names: cache-first, network-first, **stale-while-revalidate**.

**28. How do you implement offline-first?** The **local DB is the single source of truth**; UI observes the DB (stream). The repository syncs: fetch remote → upsert DB → UI updates. Writes go to the DB + an **outbox queue** retried when online (idempotency keys, conflict policy: last-write-wins/server-wins/merge). Connectivity is a hint, not truth: always handle failures.

**29. How do you test a Cubit?** `bloc_test`: mock the use case, `build` → `act` → `expect` state sequence; `seed` for starting states; cover success, failure, pagination, last page and page-2 failure.

**30. How do you test a Repository?** Mock the data source; assert model→entity mapping and each exception → failure mapping (404, 401, 422, network, parsing).

**31. How do you handle API versioning?** Version in the base URL (`/v2`) or header; keep **models per version** mapping to the **same entity**, so the domain doesn't change; migrate data sources one at a time; feature-flag the switch.

**32. How do you keep large JSON parsing off the UI thread?** `compute()`/`Isolate.run()` for payloads in the hundreds of KB (e.g. `Isolate.run(() => UsersResponseModel.fromJson(json))`); not needed for small lists, so measure first.

**33. Cursor vs page-number pagination?** Page-number/offset is simple but unstable under inserts/deletes; **cursor** tokens are stable and scale. With cursors the state stores `nextCursor` instead of `currentPage`.

**34. How do you secure the app's network layer?** HTTPS only; tokens in secure storage; never log secrets; short-lived access tokens + rotating refresh tokens; certificate pinning for high-risk apps (with a rotation plan); obfuscate release builds; validate/sanitize server data via strict models.

Cancel + cache snippets referenced above (verified):
```dart
import 'package:dio/dio.dart';

import '../feature/user/domain/entity/paged_users.dart';
import '../feature/user/domain/repository/user_repository.dart';

// ---------- 1. Cancel in-flight requests (e.g. user typed a new search term)
//   In DioClient.get(...) accept `CancelToken? cancelToken` and pass it to Dio.
//   In the Cubit:
class Cancellable {
  CancelToken? _token;

  CancelToken next() {
    _token?.cancel('superseded');
    return _token = CancelToken();
  }
}

// ---------- 2. In-memory cache with TTL, as a Repository DECORATOR.
//   UI / Cubit / UseCase don't change. DI wires CachedUserRepository(UserRepositoryImpl(...)).
class CachedUserRepository implements UserRepository {
  CachedUserRepository(this._inner, {this.ttl = const Duration(minutes: 5)});

  final UserRepository _inner;
  final Duration ttl;
  final _cache = <int, ({PagedUsers value, DateTime at})>{};

  @override
  Future<PagedUsers> getUsers({required int page}) async {
    final hit = _cache[page];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.value;

    final fresh = await _inner.getUsers(page: page);
    _cache[page] = (value: fresh, at: DateTime.now());
    return fresh;
  }
}
```

---

## SECTION 21 — The Final Live-Coding Template (memorize this)

When the interviewer says **"Integrate this API."**, think:

```text
 1. Understand JSON        → paste the response into a comment; note envelope, nullable fields, types
 2. Create Entity          → what the SCREEN needs (domain, plain Dart)
 3. Create Model           → mirror the JSON + toEntity()
 4. Create Repository IF   → abstract, returns entities, in domain
 5. Create DataSource      → endpoint + parse + (LITE) map DioException → Failure
 6. Create RepositoryImpl  → remote → toEntity()
 7. Create UseCase         → one-line call()
 8. Create Cubit           → fetch (+ loadMore)
 9. Create States          → sealed: Initial / Loading / Loaded / Error
10. Create UI              → switch on state: loader · error+retry · list
11. Connect DI             → manual in main.dart (Dio → DataSource → Repo → UseCase → Cubit)
12. Test API               → RUN. If it fails: debug bottom → top (section 18)
13. Add pagination/search  → only if asked / time remains
```

### The shortest implementation sequence (LITE, ~270 lines to a running screen)

| # | File | ~Lines | Minute |
|---|---|---|---|
| 1 | `core/constants/api_constants.dart` | 4 | 1 |
| 2 | `domain/entity/user.dart` | 15 | 3 |
| 3 | `domain/entity/paged_users.dart` | 9 | 3 |
| 4 | `data/model/user_model.dart` (+`toEntity`) | 28 | 5 |
| 5 | `data/model/users_response_model.dart` | 19 | 6 |
| 6 | `domain/repository/user_repository.dart` | 5 | 6 |
| 7 | `core/errors/failure.dart` | 5 | 6 |
| 8 | `data/data_source/user_remote_data_source.dart` | 31 | 8 |
| 9 | `data/repository/user_repository_impl.dart` | 13 | 9 |
| 10 | `domain/usecase/get_users.dart` | 10 | 9 |
| 11 | `presentation/cubit/user_state.dart` | 41 | 11 |
| 12 | `presentation/cubit/user_cubit.dart` (add `loadMore` later) | 50 | 12 |
| 13 | `presentation/pages/user_page.dart` | 55 | 14 |
| 14 | `main.dart` (manual DI) | 36 | 15 |
| ▶︎ | **RUN** | | **15** |
| 15 | `loadMore()` + footer | (in 12/13) | 18 |
| 16 | Explain | | 20 |

(If you only have time for one layer to be perfect, make it **the boundary**: interface in domain, `toEntity()`, and an error state with Retry.)

### Minute-by-minute self-check (glance at the clock)
- **min 5**: entity + model + interface done? If not → skip `UserResponse` generics, hard-code the concrete types.
- **min 9**: data layer done? If not → drop the data-source interface.
- **min 13**: Cubit + states done? If not → call repository from Cubit, say "use case next".
- **min 15**: app running? If not → debug bottom→top *now*, stop adding features.

### The 15-second close
> "That's UI → Cubit → UseCase → Repository interface → Impl → DataSource → Dio, with entities in domain and models in data. I'd harden it with typed failures, a DioClient, an auth interceptor with refresh, and tests, and I can add any of them next."

➡️ Next: reproduce **LITE** from memory on a blank project twice, against `https://reqres.in/api/users?page=1`; time it. Then once with search added.
