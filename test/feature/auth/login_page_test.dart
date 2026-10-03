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
