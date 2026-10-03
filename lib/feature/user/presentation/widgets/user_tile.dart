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
