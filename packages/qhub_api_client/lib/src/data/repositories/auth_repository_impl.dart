import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';
import '../mappers.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._dio, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Dio _dio;
  final DateTime Function() _now;

  @override
  Future<Result<AuthToken>> login({required String identifier, required String password}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/auth/token',
            data: {'identificador': identifier, 'password': password});
        final j = r.data!;
        return AuthToken(
          accessToken: j['access_token'] as String,
          expiresIn: j['expires_in'] as int,
          issuedAt: _now(),
        );
      });

  @override
  Future<Result<Registration>> register(RegisterInput input) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/auth/registro', data: registerToJson(input));
        return registrationFromJson(r.data!);
      });
}
