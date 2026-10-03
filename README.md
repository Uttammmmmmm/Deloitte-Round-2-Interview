# demoapi

Flutter REST API demo (`https://reqres.in/api`) built with **Clean Architecture + Cubit + Dio**.
Built as live-coding interview practice; the full study material is in [`docs/`](docs/)
(start with `docs/Flutter_API_Integration_Guide.pdf`).

## Run

```bash
flutter pub get
flutter run
```

## Quality gates

```bash
flutter analyze                 # strict-casts / strict-inference / strict-raw-types, 0 issues
flutter test                    # 74 tests
flutter test --coverage         # ~98% of the loaded library lines
```

Architecture self-checks (each must print nothing):

```bash
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain   # domain is pure
grep -rnE "package:dio|/data/" lib/feature/*/presentation                          # UI never sees Dio/data
find lib -name '*.dart' -size 0                                                    # no empty files
```

## Architecture

```text
UI → Cubit → UseCase → Repository (interface, domain) → RepositoryImpl → DataSource → DioClient → Dio → API
presentation ─▶ domain ◀─ data          (imports point inward)
```

```text
lib/
├── core/
│   ├── constants/   api_constants.dart            base URL, paths, timeout
│   ├── network/     dio_client.dart               5 verbs + DioException → AppException (once)
│   │                auth_interceptor.dart         Bearer token + refresh-once-on-401
│   │                safe_log_interceptor.dart     method/url/status only, debug builds
│   ├── errors/      exceptions.dart / failures.dart (+ guard)   data vs domain vocabulary
│   │                report_failure.dart / app_bloc_observer.dart  logging hook for unexpected errors
│   ├── storage/     token_storage.dart            secure storage (Keychain/Keystore)
│   └── di/          injection.dart                GetIt composition root (Cubits are factories)
├── feature/
│   ├── user/        data (model, data_source, repository) · domain (entity, repository, usecase) · presentation (cubit, pages, widgets)
│   └── auth/        same layers: POST /login, token saved by the repository
└── main.dart        routes: "/" users list · "/login"
```

Key decisions

| Decision | Why |
|---|---|
| Repository **interface in domain**, implementation in data | domain never imports data; swap/fake the data source freely |
| `Model.toEntity()` instead of `extends` | backend renames never reach the app |
| `AppException` (data) → `Failure` (domain) via `guard()` | one mapping; UI shows user-safe messages, technical cause goes to `Bloc.observer` |
| Sealed, `Equatable` states + `copyWith` | exhaustive `switch`, value equality, easy tests |
| Pagination: footer trigger + generation counter | works on short pages; stale responses are dropped |
| Cubits registered as **factories** | `BlocProvider` closes them; a singleton would be closed after the first visit |
| Auth in an interceptor | no repository/Cubit ever touches a token |

## API notes

reqres.in is a public demo API: about 20 requests/minute, 6 users per page, `/login`
works with `eve.holt@reqres.in` / `cityslicka`.
