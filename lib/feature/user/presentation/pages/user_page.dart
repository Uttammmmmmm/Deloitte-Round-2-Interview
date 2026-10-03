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
