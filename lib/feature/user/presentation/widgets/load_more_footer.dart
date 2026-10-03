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
