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
