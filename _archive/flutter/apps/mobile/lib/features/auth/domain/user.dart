import 'package:qhub_core/qhub_core.dart';

class AppUser {
  const AppUser({required this.id, required this.email, this.displayName});
  final String id;
  final String email;
  final String? displayName;

  String get firstName => (displayName ?? '').split(' ').firstWhere((s) => s.isNotEmpty, orElse: () => '');
}

abstract interface class UserRepository {
  AppUser? get currentUser;
  Stream<AppUser?> authChanges();
  Future<Result<AppUser>> signIn({required String email, required String password});

  /// `null` = el proyecto exige confirmar el correo antes de entrar.
  Future<Result<AppUser?>> signUp({required String email, required String password, required String firstName, required String lastName});
  Future<Result<void>> signOut();
}
