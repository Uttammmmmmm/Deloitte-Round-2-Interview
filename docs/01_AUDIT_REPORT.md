# Phase 1 — Audit of `demoapi` (Flutter · Clean Architecture · Cubit · Dio)

> Auditor stance: strict senior Flutter interviewer (Deloitte-style live-coding round).
> Scope: every file under `lib/` and `test/` as it exists today, plus `pubspec.yaml`.
> Evidence: `flutter analyze` → **0 issues** (compiles, lints clean) · `flutter test` → **1 failing test** (the untouched Flutter counter template; crashes with `LateInitializationError: Field 'userCubit' has not been initialized`).
> **Note:** this audit describes the code **as it was before the fix**. The fixes in Part 2 have since been applied to the project (original code backed up in `demoapi_backup_before_100/`).
> Lesson already visible: *"analyzer-clean" is not "architecture-clean".* Your code compiles, but the dependency rule is broken in two files and the error layer is empty.

---

## 0. Verdict in 60 seconds

| | |
|---|---|
| **Score** | **39 / 100** (rubric in §9) |
| **Class** | **Beginner → Intermediate border.** Structure is Intermediate. Execution (dependency direction, errors, pagination, tests) is Beginner. Not yet Interview Ready. |
| **Good news** | Almost all of it is fixable in ~25 minutes of focused editing, and the *shape* is right: feature-first folders, interface in domain / impl in data, UseCase → Cubit, sealed states, Dio injected, DI chain in the right order. |
| **Worst problem** | `domain/` imports from `data/` (2 files). In Clean Architecture that is the single most checked rule. An interviewer who opens `user_repository.dart` sees line 1 and the conversation changes tone. |
| **Second worst** | `core/erros/exceptions.dart` and `failuers.dart` are **empty (0 bytes)**; the data source throws a bare `Exception(e.message)` and the Cubit shows `e.toString()`. Zero real error handling. |
| **Third worst** | Half-built pagination: `isLoadingMore`, `totalPages`, `currentPages` exist in state but nothing ever uses them. |

---

## 1. Clean Architecture audit

### 1.1 What the dependency direction *should* be

There are two different arrows people mix up. Interviewers love this distinction.

```text
CALL direction (who invokes whom at runtime)
UI → Cubit → UseCase → Repository(interface) → RepositoryImpl → DataSource → Dio → API

DEPENDENCY direction (who imports whom at compile time)
presentation ──▶ domain ◀── data
                   ▲
          (domain imports NOTHING from the other two,
           and nothing from Flutter or Dio)
```

`RepositoryImpl` is called *through* the interface, but it **imports** the domain (to implement it). That inversion (Dependency Inversion Principle) is what "Clean" means.

### 1.2 Checklist against your code

| Question you asked | Verdict | Evidence |
|---|---|---|
| Does **Domain depend on Data**? | ❌ **YES — violation** | `lib/feature/user/domain/repository/user_repository.dart:1` → `import '../../data/model/user_response.dart';` and `lib/feature/user/domain/usecase/get_users.dart:1` → `import 'package:demoapi/feature/user/data/model/user_response.dart';` |
| Does the **UI call Dio** directly? | ✅ No | `user_page.dart` only imports cubit/state. |
| Does the **Cubit call Dio** directly? | ✅ No | `UserCubit` takes `GetUsers`. |
| Is the **repository interface in Domain**? | ⚠️ Yes by location, ❌ by content | It lives in `domain/repository/` but its return type is a *data-layer* class, so it is not really a domain contract. |
| Is the **repository implementation in Data**? | ✅ Yes | `data/repositories/user_repository_impl.dart` |
| Are **Models leaking into Presentation**? | ⚠️ Indirectly | `UserResponse` (a `data/model` class) flows through UseCase into the Cubit (`response.users`, `response.page`). The Cubit file never imports it, so the leak is hidden by type inference, which is worse because it is hard to spot. |
| Are **Entities separated from Models**? | ⚠️ Half | `User` ↔ `UserModel` is separated (via `extends`). The paginated wrapper is not: `UserResponse` is a business-shaped class stored in `data/model/`, and `UserResponseModel extends UserResponse` holds `List<User>` (entities) inside a model. |
| Are **use cases useful** or unnecessary? | ⚠️ Pass-through | `GetUsers.call` = `repository.getUsers(page: page)`. For *interview* purposes keep it (it is the expected layering and a seam for rules). Just be ready to defend it (see Q5). |
| Is the **data source responsibility** correct? | ⚠️ Mostly | It does HTTP + parse (right) but also builds the absolute URL (`'${ApiConstants.baseUrl}${ApiConstants.users}'`, `user_remote_source_source.dart:16`) and converts errors (wrongly, see §3). Base URL belongs in Dio's `BaseOptions`. |

### 1.3 Concrete issues (ordered by damage)

1. **Domain → Data import (2 files).** Root cause: `UserResponse` is in the wrong layer. It is `{page, perPage, total, totalPages, users}`, i.e. a *business concept* ("a page of users"). Move to `domain/entity/`, rename to `PagedUsers`, drop `perPage`/`total` (no screen uses them: YAGNI).
2. **Interface file and implementation file names are swapped.**
   - `data-source/user_remote_data_source_impl.dart` contains the **abstract** `UserRemoteDataSource`.
   - `data-source/user_remote_source_source.dart` contains the **Impl** (and the filename has "source_source").
   Anyone navigating by filename opens the wrong class. In a screen-share this costs seconds and credibility.
3. **Typos baked into paths:** `core/erros/`, `failuers.dart`, `user_title.dart` (should be `user_tile`), `data-source/` (hyphen; Dart convention is `snake_case`), `repositories` vs `repository`. Rename now; typos in folder names look careless when imports are visible on screen.
4. **Empty files committed:** `exceptions.dart`, `failuers.dart`, `user_title.dart` are 0 bytes. Either implement or delete; never leave dead scaffolding in front of an interviewer.
5. **Dead code:** `core/network/dio_client.dart` (GET-only wrapper) is never used. `Injection.dio` is a bare `Dio()`. Two half-ideas competing.
6. **Mixed import styles:** `package:demoapi/...` in cubit/usecase/page, relative in the rest. Pick one (the guide uses package imports for cross-layer, relative within a file's own folder tree is fine; just be consistent).

### 1.4 Over-engineered?

| Item | Verdict |
|---|---|
| 4 classes for one list (`User`, `UserModel`, `UserResponse`, `UserResponseModel`) | Slightly. 4 is right *if* mapped properly with `toEntity()`; today they relate by inheritance, which is the confusing part, not the count. Target: `User`, `PagedUsers` (domain) + `UserModel`, `UsersResponseModel` (data). |
| `UserModel.toJson()` | Unused for GET: YAGNI. Keep only when you POST that shape. |
| DataSource interface | Optional in a 20-min round (mocktail can mock the concrete class). Keep it because the prompt/interviewer expects it; skip it *first* if you are behind. |
| A separate `Injection` class with `static late` fields | Over-built and dangerous (see §6). |

---

## 2. BLoC / Cubit audit

| Area | Verdict | Evidence / why |
|---|---|---|
| Responsibility | ✅ | Cubit only orchestrates `GetUsers` → emit. No Dio, no JSON. |
| Calls the right abstraction | ✅ | `GetUsers` (use case), not the repository impl. |
| State design | ⚠️ | `sealed` hierarchy is the right idea. Missing `Equatable` (it's in your `pubspec.yaml` but unused) → states have no value equality: duplicate emissions rebuild, and tests can't `expect(..., [UserLoading(), UserLoaded(...)])`. |
| Loading / Success / Error | ✅/⚠️ | Present. Error is `e.toString()` → user sees `Exception: Something went wrong`. |
| **Pagination state** | ❌ | `UserLoaded` has `isLoadingMore`, `currentPages` (typo: plural), `totalPages`; **no code ever sets `isLoadingMore`**, there is no `loadMore()`, and `fetchUsers(page:)` *replaces* the list instead of appending. |
| Loading-more state | ❌ | See above: dead field. |
| Immutability | ⚠️ | Fields are `final` ✅, but no `copyWith` (needed for append) and `List<User>` is exposed mutable (low risk). |
| Business logic in UI | ✅ | None. But the UI also does no work for pagination (no trigger). |
| Business logic in Cubit | ⚠️ | Fine today; will bloat once pagination is added without guards (duplicate calls). |
| `catch (e)` | ❌ | Catches *everything*, including programmer errors (`TypeError`, `StateError`), then prints them to users. Catch the typed `Failure` only. |
| Lifecycle | ❌ | No `if (isClosed) return;` before `emit` after `await`. User leaves the screen mid-request → `emit` on a closed Cubit. |
| Created via DI | ❌ | `Injection.userCubit` is a **singleton** (`injection.dart:27`) handed to `BlocProvider(create:)` (`main.dart:21`). `BlocProvider` closes what it creates on dispose → the next time the screen is built the *closed* instance is reused → "Cannot emit new states after calling close". Cubits are **factories**. |
| `initState` + `context.read` | ⚠️ | `user_page.dart:16-19` works but leaves a `// TODO: implement initState` comment and couples fetching to widget lifecycle. Prefer `create: (_) => sl<UserCubit>()..fetchUsers()`. |

### Is `UI → Cubit → UseCase` appropriate?

Yes. The Cubit is the **presentation logic holder** (what state does the screen show?). The UseCase is the **application action** (get users). The repository is the **data gateway**. The Cubit should never know *how* data is fetched, only *what* to ask for. For a simple list the use case is thin; its value is (1) a single named business action per file, (2) a place for rules (validation, combining repositories), (3) trivially mockable in Cubit tests.

### Cubit vs Bloc for a live-coding interview

| Use **Cubit** (default) | Use **Bloc** when… |
|---|---|
| Direct methods (`fetchUsers()`), less boilerplate, faster to type and to explain | Events must be **traced/logged**, or you need **event transformers** (`restartable()` for search, `droppable()` for pagination, `debounce`) |
| Request/response style screens: list, details, login, form submit | Many different triggers mutate the same state, or you need replay/undo/analytics on "what happened" |
| 20-minute budget | The interviewer says "use Bloc", or the problem is clearly event-driven (typing search + pagination + refresh racing each other) |

Say this in the interview: *"I'll use Cubit for speed and clarity; if search + pagination start racing I'd switch that screen to Bloc to get `restartable()`."*

---

## 3. API integration audit

| Area | Verdict | Evidence / comment |
|---|---|---|
| Dio configuration | ❌ | `Dio()` with defaults (`injection.dart:19`): no `baseUrl`, no timeouts, no headers. Dio has no default timeout of its own, so a dead connection hangs until the OS gives up (often a minute or more): the user stares at a spinner. |
| Base URL | ⚠️ | In `ApiConstants`, but concatenated by hand at the call site. Belongs in `BaseOptions(baseUrl: …)` so endpoints are just `'/users'`. |
| Endpoints | ⚠️ | Constant exists (`users`) ✅, but base URL and path are both concatenated. |
| Query params | ✅ | `{'page': page}` is correct. |
| Headers | ❌ | None (not even `Accept`). Fine for reqres today, but you can't show where tokens/headers would go. |
| HTTP methods | ❌ | Only GET exists. The unused `DioClient` only wraps GET. Adding POST/PUT/PATCH/DELETE means copy-pasting the same `try/catch` into every data-source method (violates DRY). |
| Response parsing | ⚠️ | `response.data as Map<String, dynamic>` ✅. But `json['id'] ?? 0`, `?? ''`, `?? []` **invent data** when the contract breaks (a user with id 0 and empty email renders as a blank tile). Prefer failing loudly (`as int`) and map the failure to a `ParsingFailure`. |
| JSON serialization | ✅ | Hand-written `fromJson` is the right call for an interview (no codegen to wait for). |
| Error handling | ❌❌ | `catch (DioException e) { throw Exception(e.message ?? 'Something went wrong'); }` (`user_remote_source_source.dart:21-23`). Loses status code and error type. For `badResponse`, `e.message` is often null, so *every* error becomes "Something went wrong". 401, 404, timeout, offline are indistinguishable. Server's body `{"error": "Missing password"}` is thrown away. |
| Timeout handling | ❌ | None. |
| API vs network exceptions | ❌ | Not distinguished. |
| Empty response | ⚠️ | `?? []` handles missing `data`, but there is no *empty state* in the UI (`ListView` of 0 items = blank screen). |
| Invalid response | ❌ | `TypeError`/`FormatException` from parsing isn't mapped; `catch (e)` in the Cubit prints a raw Dart error. |

**Can it easily support GET / POST / PUT / PATCH / DELETE?** Not today. The *architecture* can, but the *data layer plumbing* isn't there: each verb would duplicate try/catch + error mapping. A single wrapper (`DioClient` with `get/post/put/patch/delete` + one `_send` that converts `DioException` → `AppException`) turns every future endpoint into 2–3 lines. You already started that class and abandoned it; finishing it is the fix.

---

## 4. Model vs Entity audit

**Current approach:** `UserModel extends User`, `UserResponseModel extends UserResponse`.

| | `extends` (current) | `toEntity()` (recommended) |
|---|---|---|
| Typing speed | Fastest: `super.id`… | +6–8 lines per model (`toEntity()`) |
| Domain independence | ❌ `User` is a plain class, fine, but the pattern invites putting `fromJson` on the entity "since it's one step" | ✅ Entity never knows JSON exists |
| Backend renames a field | Breaks `User` and everything above it | Only `UserModel.fromJson` changes |
| Model has extra fields (`perPage`, `total`, `meta`) the entity doesn't want | Impossible without bloating the entity | Natural |
| Where it hurt **you** | `UserResponse` ended up in the data layer *because* the model extended it, which pulled the domain contract into data. That is the exact failure mode of the shortcut. | n/a |
| Clarity in interview | "It's a subtype" (interviewer: *so the domain is shaped like the JSON?*) | "Model parses, entity is business, mapper between them" (one sentence, no follow-up) |

**Recommendation.** *Live coding:* use **`toEntity()`**. It's ~30 seconds more typing and removes an entire line of follow-up questions. If you are genuinely out of time, `extends` is acceptable **only if the entity still lives in `domain/` and has no JSON code**; say out loud: *"Shortcut for time; production code maps with toEntity()."* *Production:* always `toEntity()` (or `freezed` + mappers).

Other findings:
- `json['id'] ?? 0` silently turns bad data into valid-looking data. Use `as int` and let `guard()` convert `TypeError` → `ParsingFailure`.
- `User` has no `==`/`hashCode`: list equality in states/tests fails. Make entities `Equatable`.
- The UI builds `'${user.firstName} ${user.lastName}'` inline; a `fullName` getter on the entity is a cleaner single source.

---

## 5. Repository pattern audit

| | Verdict |
|---|---|
| `UserRepository` (interface) in Domain | ✅ location, ❌ content (returns data-layer `UserResponse`). |
| `UserRepositoryImpl` in Data | ✅ location. Body is pass-through: **no exception → failure mapping**, which is the repository's main job. |
| UI doesn't know the implementation | ✅ UI → Cubit → UseCase → *interface*. (The only place that knows `UserRepositoryImpl` is the DI file: correct.) |
| Testability | ⚠️ In theory excellent (swap in a fake repository; see widget test in the guide). In practice zero tests exist. |

Why the interface belongs in Domain: the *domain* defines what it needs ("give me a page of users"); the *data* layer adapts to that need. If the interface lived in data, domain would have to import data to use it, reversing the dependency. Why UI must not know the implementation: so swapping REST → GraphQL → cache → fake requires **zero** changes above the interface. Why it makes testing easy: a `Mock`/`Fake` implementing a 1-method interface is 3 lines; no HTTP, no Dio.

---

## 6. Dependency injection audit

Your chain:

```text
Dio → RemoteDataSource → RepositoryImpl → GetUsers → UserCubit → UI
```

**Order: correct ✅.** Types on the left-hand side are the interfaces (`UserRemoteDataSource`, `UserRepository`) ✅ (that's DIP in the DI file).

| Issue | Where | Why it matters |
|---|---|---|
| `static late` mutable globals | `injection.dart:11-16` | Any code can reassign them; reading before `init()` crashes with `LateInitializationError`, which is **exactly why your `flutter test` is red**. |
| Cubit is a singleton | `injection.dart:27` | Closed-cubit bug described in §2. Use `registerFactory`. |
| `get_it` in `pubspec.yaml` but unused | pubspec | Reviewer reads that as unfinished. Use it or remove it. |
| 4 of the 5 `static late` fields are only there to hold intermediate objects | `injection.dart` | Only the *composition* matters; nothing needs to be stored. |
| `Dio()` unconfigured | `injection.dart:19` | See §3. |

**GetIt or manual for 20 minutes?** **Manual first**, composed once in `main.dart` (a "composition root"): 6 lines, zero packages, zero ceremony, and easy to explain (*"one place knows all concrete classes"*). Move to **GetIt** only if (a) the interviewer asks how it scales, or (b) you already have 2+ features. Migration is mechanical (the guide shows both). The *fastest clean* version is:

```dart
final repository = UserRepositoryImpl(UserRemoteDataSourceImpl(DioClient(dio)));
BlocProvider(create: (_) => UserCubit(GetUsers(repository))..fetchUsers(), child: const UserPage());
```

---

## 7. Folder structure audit

Your tree is **the right shape**, with the wrong spelling:

```text
lib/
├── core/{constants, di, erros✗, network}      → errors
├── feature/user/
│   ├── data/{data-source✗, model, repositories✗}  → data_source, repository
│   ├── domain/{entity, repository, usecase}       ✅ (add paged_users.dart here)
│   └── presentation/{cubit, pages, widget✗}       → widgets
└── main.dart
```

| Rename / move | Why |
|---|---|
| `core/erros` → `core/errors`; `failuers.dart` → `failures.dart` | Typos |
| `data-source/` → `data_source/` | Dart naming convention (`snake_case` everywhere) |
| `data/repositories/` → `data/repository/` | Consistent with `domain/repository/` (same word both sides is easier to find) |
| `presentation/widget/user_title.dart` (empty) → `presentation/widgets/user_tile.dart` | Typo + give it content (move the `ListTile` out of the page) |
| `data/model/user_response.dart` → `domain/entity/paged_users.dart` | Fixes the dependency violation |
| Swap contents of the two data-source files | Names must match classes |

Do **not** add more folders (no `utils/`, `helpers/`, `services/`, `bloc/` + `cubit/`). Add `core/storage/` only when you implement token storage.

---

## 8. SOLID / DRY / KISS / YAGNI

| Principle | Verdict | Why |
|---|---|---|
| **S**ingle responsibility | ⚠️ | Classes are small ✅. Data source also builds absolute URLs and converts errors; DI class also *stores* the object graph. |
| **O**pen/closed | ⚠️ | Adding another feature = new folder + a few lines in `Injection` ✅. Adding a verb/endpoint means copy-pasting try/catch (modifies by duplication) ❌. |
| **L**iskov | ✅ | `UserRemoteDataSourceImpl` / `UserRepositoryImpl` fully honour their interfaces. |
| **I**nterface segregation | ✅ | Both interfaces have one method. |
| **D**ependency inversion | ❌ | Domain imports data (§1). Everything else injected via interfaces ✅. |
| **DRY** | ⚠️ | No duplication *yet* because there's only one endpoint; the design duplicates as soon as a second appears (try/catch). |
| **KISS** | ✅ | Easy to read. |
| **YAGNI** | ⚠️ | Unused: `DioClient`, `toJson`, `UserResponse.perPage/total`, `isLoadingMore`, `equatable`, `get_it`, empty files. Unused code is worse than missing code: interviewers ask "what is this for?". |
| Separation of concerns | ⚠️ | UI/state/data split ✅; domain/data boundary ❌. |

---

## 9. Live-coding score (strict)

```text
Architecture             8 /20   Right layers & folders; domain→data import; swapped/typo'd files
BLoC/Cubit               6 /15   Sealed states + UseCase injection ✓; no loadMore, no Equatable, catch(e), singleton, no isClosed
API Integration          6 /15   Dio + query param ✓; no baseUrl/timeouts/headers/verbs, DioClient unused
Model/Entity Design      4 /10   Separated, but by inheritance; response wrapper in wrong layer; `?? 0` defaults
Repository Pattern       5 /10   Interface/impl split ✓; contract imports data; no exception→failure mapping
Error Handling           1 /10   Two empty files; bare Exception(message); toString() to the user
Dependency Injection     2 /5    Correct order ✓; static late, singleton cubit, get_it unused
Code Quality             2 /5    Typos, TODO, empty files, mixed imports, red test
SOLID/DRY/KISS           2 /5    DIP broken; unused code; will duplicate on 2nd endpoint
Live Coding Speed        3 /5    Compact & fast to type; but would lose time on swapped names & missing pieces

TOTAL                   39 /100

Overall Score: 39/100
```

Scale used: `0–39 Beginner · 40–59 Intermediate · 60–74 Interview Ready · 75–89 Production Ready · 90+ Senior Level`.

**Classification: Beginner (upper edge) / Intermediate structure.** One edit (move `UserResponse` into `domain/` as `PagedUsers`) is worth about +6. The full fix list in §11 lifts it to the high 80s on this same rubric (the reference implementation in the guide is built to that bar, compiles with 0 analyzer issues, and has 74 passing tests).

---

## 10. The 20 questions an interviewer will ask about *your* implementation

🚩 = exposes a weakness in your **current** code. The ideal answers assume the fixed code from the guide.

**Q1 🚩. Why did you put the repository interface inside Domain?**
- *Say (25 s):* "Because the domain defines what it needs and the data layer adapts to it. If the interface were in data, the domain would import data and the dependency would point the wrong way. Domain stays pure Dart: no Flutter, no Dio, no JSON. That also lets me swap REST for a cache or a fake without touching use cases or UI."
- *Why asked:* Tests whether you understand Dependency Inversion, not just folder names.
- *Real world:* Moving from REST to GraphQL: only `UserRepositoryImpl` + a new data source change.

**Q2 🚩. Your `UserResponse` is in `data/model` but the use case returns it. Is that okay?**
- *Say:* "No, that's a layering bug. It's a business concept ('a page of users'), so it belongs in domain as `PagedUsers`. The data layer has `UsersResponseModel` which parses JSON and maps to it with `toEntity()`."
- *Why:* They will literally open the file you imported. This is the #1 trap in your current code.
- *Real world:* A backend renames `total_pages` → `pages`: only the model changes; the use case and Cubit are untouched.

**Q3. Why both a Model and an Entity? They have the same fields.**
- *Say:* "Different reasons to change. The model mirrors the API (snake_case, nullable, extra fields). The entity mirrors the app's needs. Today the fields match; when the backend changes shape, only the model and mapper change."
- *Why:* Detects cargo-cult architecture vs. understanding.
- *Real world:* API v2 returns `name` instead of `first_name`/`last_name`; the entity keeps both, mapper splits.

**Q4. Why `toEntity()` instead of `UserModel extends User`?**
- *Say:* "Inheritance couples the data shape to the domain shape and invites JSON code onto the entity. A mapper is eight lines and keeps the boundary explicit. If I were truly out of time I'd extend and say so, but I'd keep the entity in domain."
- *Why:* Trade-off judgement.
- *Real world:* Adding a computed `isPremium` to the entity without touching serialization.

**Q5. This use case is one line. Why does it exist?**
- *Say:* "It names the business action and gives one seam for rules and orchestration. Today it's thin; the first time we need validation, caching policy, or combining two repositories, there's a home for it, and the Cubit doesn't change. For pure CRUD I'd accept calling the repository directly."
- *Why:* Checks you're not dogmatic.
- *Real world:* `PlaceOrder` validates stock then calls two repositories.

**Q6. Why Cubit instead of Bloc?**
- *Say:* "This screen is request/response: load, load more, retry. Methods are enough. I'd move to Bloc if I needed event transformers like `restartable()` for search or an event log."
- *Why:* Knowing when to switch matters more than the choice.
- *Real world:* A search+filter+pagination screen that races: `restartable()` cancels stale searches.

**Q7. Why `sealed` states and `Equatable`?**
- *Say:* "Sealed lets the compiler force me to handle every state in a `switch`: add a state and the UI won't compile until handled. Equatable gives value equality, so identical emissions don't rebuild, and tests can compare states directly."
- *Why:* Checks Dart 3 fluency and testability thinking.
- *Real world:* Adding `UserEmpty`: every `switch` in the app flags it.

**Q8 🚩. How do you stop duplicate "load more" calls while scrolling?**
- *Say:* "`loadMore()` returns early if the state isn't `UserLoaded`, or `isLoadingMore` is true, or `hasReachedMax`. The scroll can fire a hundred times; the Cubit lets one through. With Bloc I'd use the `droppable()` transformer."
- *Why:* Classic bug: duplicate pages / duplicate rows.
- *Real world:* Page 3 appended twice because two scroll events fired before `isLoadingMore` flipped.

**Q9. Difference between initial loading and pagination loading?**
- *Say:* "Initial loading has no data yet, so a full-screen spinner and a separate `UserLoading` state. Pagination loading already has data on screen, so I keep the list and set `isLoadingMore` to show a footer spinner. Replacing the list with a spinner on page 2 would make the list jump."
- *Why:* UX + state-modelling.
- *Real world:* Instagram feed: bottom spinner, not blank screen.

**Q10 🚩. What happens if page 2 fails?**
- *Say:* "The list stays. I reset `isLoadingMore`, set `loadMoreFailed`, and the footer shows a Retry. I don't replace the loaded screen with a full-screen error."
- *Why:* Probes whether error states were thought through beyond the happy path.
- *Real world:* Elevator on bad signal: user already read 20 items; don't wipe them.

**Q11 🚩. Walk me through error handling end to end.**
- *Say:* "Dio throws `DioException`. `DioClient` converts that once into an `AppException` (`ServerException` with status code, or `NetworkException` for timeout/offline). The repository's `guard()` converts exceptions to `Failure` (Unauthorized, Validation, Server, Network, Parsing, Unknown). The Cubit catches only `Failure` and emits an error state with a user-safe message. Nothing above the repository sees Dio."
- *Why:* Core competence; your current files are empty.
- *Real world:* 401 → `UnauthorizedFailure` → global listener sends user to login.

**Q12 🚩. Why `on Failure catch` and not `catch (e)`?**
- *Say:* "`catch (e)` also swallows programmer bugs (`TypeError`, `StateError`) and shows them to users as if they were network problems. The repository guarantees only `Failure` escapes, so the Cubit catches exactly that and real bugs still surface in crash reporting."
- *Why:* Error-handling maturity.
- *Real world:* A null-check bug hidden as "Something went wrong" for weeks.

**Q13. Why wrap `DioException` instead of letting it bubble up?**
- *Say:* "So no layer above data depends on Dio. If I replace Dio with `http`, only `DioClient` changes. Also `DioException` isn't user-friendly: I need status code, server message, and a type I can switch on."
- *Why:* Encapsulation of third-party packages.
- *Real world:* Swapping packages after a security advisory.

**Q14 🚩. Your `fromJson` uses `?? 0` and `?? ''`. Is that safe?**
- *Say:* "No: it hides contract breaks by inventing valid-looking data. I cast strictly; a wrong shape throws `TypeError`, `guard()` maps it to `ParsingFailure`, and it shows up in monitoring. I use `?` / defaults only for fields that are genuinely optional in the API contract."
- *Why:* Data-integrity thinking.
- *Real world:* A user with id 0 and blank email silently written to a local DB.

**Q15 🚩. Why is the Cubit registered as a factory, not a singleton?**
- *Say:* "`BlocProvider(create:)` closes the Cubit when the widget is disposed. A singleton would be closed after the first visit and the second visit would emit into a closed Cubit. Stateless things (repository, use case, Dio) are singletons; Cubits are per-screen factories."
- *Why:* Lifecycle understanding; this is a real bug in your current DI.
- *Real world:* "Works the first time, crashes when I come back to the screen."

**Q16. GetIt or manual DI? Why?**
- *Say:* "For one feature, a composition root in `main.dart` is simplest: one place knows the concrete classes. GetIt pays off with many features, lazy singletons, and test overrides. The wiring order is identical: Dio → client → data source → repository → use case → Cubit."
- *Why:* Pragmatism vs tool-worship.
- *Real world:* Team of 10 with 15 features → GetIt/injectable.

**Q17 🚩. Where do base URL, timeouts, headers, and logging live?**
- *Say:* "On the Dio instance (`BaseOptions` + interceptors), created once in the composition root. Endpoints are relative paths in `ApiConstants`. Auth header and token refresh are an interceptor, so no repository or Cubit touches tokens."
- *Why:* Config centralisation.
- *Real world:* Switching staging ↔ production by changing one constant/flavour.

**Q18 🚩. How would you add POST, PUT, PATCH and DELETE?**
- *Say:* "`DioClient` already exposes all five verbs with one shared `_send` that maps errors. A new endpoint is: request model (toJson), response model (fromJson/toEntity), a data-source method, a repository method, a use case, and a Cubit method or its own Cubit. Same six steps every time."
- *Why:* Is the architecture a pattern or one-off?
- *Real world:* Create/Edit/Delete user screens.

**Q19 🚩. How would you test this?**
- *Say:* "Cubit with `bloc_test` and a mocked use case: success, failure, pagination, last page. Repository with a mocked data source: exceptions map to the right failures, and model maps to entity. `DioClient` with a mocked Dio: status codes map to exceptions. One widget test with a fake repository."
- *Why:* Testing is why the architecture exists. Your repo currently has only the failing template test.
- *Real world:* CI blocks merges on red tests.

**Q20. How would you add auth tokens and refresh without touching repositories?**
- *Say:* "A Dio interceptor: `onRequest` adds the Bearer token from secure storage; `onError` on 401 refreshes once using a separate Dio (so the refresh call can't recurse), stores the new token and retries the original request. Parallel 401s share one refresh future. If refresh fails: clear storage, emit `UnauthorizedFailure`, UI navigates to login."
- *Why:* Senior-level cross-cutting concern.
- *Real world:* Every banking/health app.

---

## 11. What to change: exact, ordered list (≈25 min)

| # | Change | Files | Fixes |
|---|---|---|---|
| 1 | Move `UserResponse` → `domain/entity/paged_users.dart` as `PagedUsers {users, page, totalPages, hasNext}`; fix imports in `user_repository.dart` and `get_users.dart`; **delete** `data/model/user_response.dart` | domain/*, data/model/* | §1 DIP violation |
| 2 | Models parse, entities are business: add `toEntity()` to `UserModel` and `UsersResponseModel`; remove `extends`; strict `as` casts instead of `?? 0` | data/model/* | §4 |
| 3 | Error layer: implement `exceptions.dart` + `failures.dart` + `guard()`; make `DioClient` real (all 5 verbs + `_toException`); repository wraps in `guard()` | core/errors/*, core/network/dio_client.dart, repository impl | §3 error handling |
| 4 | Configure Dio (`baseUrl`, timeouts, `Accept` header); data source uses `DioClient` and relative path `'/users'` | injection, data source | §3 |
| 5 | Cubit: `Equatable` states + `copyWith`; `fetchUsers()` / `loadMore()` with guards; `on Failure catch`; `isClosed`; DI `registerFactory`; UI: `LoadMoreFooter`, `ErrorView` with Retry | cubit/*, page, widgets/* | §2, §6 |
| 6 | Rename: `erros→errors`, `failuers→failures`, `data-source→data_source` (and swap the two files' contents), `repositories→repository`, `widget→widgets`, `user_title→user_tile` | everywhere | §7 |
| 7 | Replace the counter test with real tests (cubit, repository, DioClient, one widget test) | test/* | §9 Code quality |
| 8 | Use GetIt or remove it from `pubspec.yaml`; same for any unused import/dependency | pubspec, injection | YAGNI |

**Self-check commands for interview morning** (each should print nothing):

```bash
# Domain must not import data, presentation, Flutter or Dio
grep -rnE "data/|presentation/|package:flutter|package:dio" lib/feature/*/domain

# Presentation must not import Dio or data models
grep -rnE "package:dio|/data/" lib/feature/*/presentation

# No empty files
find lib -name '*.dart' -size 0
```

---

## 12. Final block

```text
CURRENT IMPLEMENTATION SCORE: 39/100

TOP 5 CHANGES REQUIRED:
1. Domain must not import Data: move UserResponse → domain/entity/paged_users.dart (PagedUsers),
   fix user_repository.dart:1 and get_users.dart:1.
2. Build the error layer: exceptions.dart + failures.dart + guard(); finish DioClient (5 verbs,
   DioException→AppException); Cubit catches `on Failure`, shows a user-safe message.
3. Finish pagination: Equatable states + copyWith, fetchUsers()/loadMore() with duplicate/last-page
   guards, footer loader + Retry, `if (isClosed) return;`.
4. Model→Entity with toEntity() (drop `extends`, drop `?? 0` defaults) + configure Dio
   (baseUrl, timeouts, headers) + Cubit as GetIt factory (or manual DI in main.dart).
5. Fix names/dead code (erros, failuers, data-source swap, user_title, DioClient/toJson unused),
   and replace the red counter test with real cubit/repository/DioClient tests.

20-MINUTE TARGET ARCHITECTURE:
   UI(page+widgets) → Cubit(+Equatable states) → UseCase → Repository(interface, domain)
   → RepositoryImpl(guard: Exception→Failure) → RemoteDataSource(Model parse)
   → DioClient(5 verbs, DioException→AppException) → Dio(BaseOptions) → API
   Dependencies point inward: data → domain ← presentation.

MEMORIZATION FORMULA:
   E-M-R-D-I-U-C-S-U  →  Entity, Model, Repository(interface), Data source, Impl,
   Use case, Cubit, States, UI  (+ DI, run, then pagination/search)
   Response flow: API → JSON → Model → toEntity() → Repository → UseCase → Cubit → State → UI
   Error flow:    DioException → AppException → Failure → Cubit → Error state → Retry
```

➡️ Continue with **`02_API_INTEGRATION_GUIDE.md`**: every code block there was compiled and tested.
