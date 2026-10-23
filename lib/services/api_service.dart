import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String kGoogleAppScriptUrl = String.fromEnvironment(
  'GOOGLE_SCRIPT_URL',
  defaultValue:
      'https://script.google.com/macros/s/AKfycbzTyeGbg6swtTAumqN8oGSdEtJ0uNG5MuW3H1UW1lO3iy1AbdxGQlKZkCqYfa0JEVDd/exec',
);

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.accountNumber = '',
    this.profileImageUrl = '',
    this.permissions = const {},
    this.reportAccess = const {
      'daily': true,
      'weekly': true,
      'monthly': true,
    },
  });

  final String token;
  final String userId;
  final String name;
  final String email;
  final String role;
  final String accountNumber;
  final String profileImageUrl;
  final Map<String, bool> permissions;
  final Map<String, bool> reportAccess;

  bool hasPermission(String permission) =>
      role.toLowerCase() == 'admin' || permissions[permission] == true;

  bool canViewReport(String report) =>
      role.toLowerCase() != 'member' || reportAccess[report] == true;

  AuthSession copyWith({
    String? name,
    String? email,
    String? profileImageUrl,
  }) =>
      AuthSession(
        token: token,
        userId: userId,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role,
        accountNumber: accountNumber,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        permissions: permissions,
        reportAccess: reportAccess,
      );

  bool matchesMemberName(Object? rowMemberName) {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return normalize(rowMemberName?.toString() ?? '') == normalize(name);
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<dynamic> _request(
    Map<String, dynamic> payload, {
    bool authenticationAction = false,
    bool retryOnBusy = true,
  }) async {
    try {
      var response = await _client
          .post(
            Uri.parse(kGoogleAppScriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if ((response.statusCode == 301 || response.statusCode == 302) &&
          response.headers['location'] != null) {
        response = await _client
            .get(Uri.parse(response.headers['location']!))
            .timeout(const Duration(seconds: 20));
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException('Server returned status ${response.statusCode}.');
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        if (response.body.toLowerCase().contains('unknown post action')) {
          throw ApiException(_unsupportedActionMessage(payload['action']));
        }
        throw const ApiException('The server returned an invalid response.');
      }

      if (data is String &&
          data.toLowerCase().contains('unknown post action')) {
        throw ApiException(_unsupportedActionMessage(payload['action']));
      }
      if (data is Map && data['status'] == 'error') {
        final message = data['message']?.toString() ?? 'The request failed.';
        final normalized = message.toLowerCase();
        if (retryOnBusy &&
            normalized == 'the service is busy. please try again.') {
          // Lock failures happen before the server runs the action, so retrying
          // this response cannot duplicate a successful write.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _request(
            payload,
            authenticationAction: authenticationAction,
            retryOnBusy: false,
          );
        }
        if (normalized.contains('unknown post action') ||
            (authenticationAction &&
                (normalized.contains('unknown action') ||
                    normalized.contains('invalid action') ||
                    normalized.contains('unsupported action')))) {
          throw ApiException(_unsupportedActionMessage(payload['action']));
        }
        throw ApiException(message);
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (error) {
      debugPrint('API request failed: $error');
      throw const ApiException(
        'Could not connect to the service. Check your connection and try again.',
      );
    }
  }

  String _unsupportedActionMessage(dynamic action) {
    switch (action) {
      case 'login':
        return 'The server does not support email/password login yet. Add a login action to Apps Script doPost and redeploy.';
      case 'register':
        return 'The server does not support registration yet. Add a register action to Apps Script doPost and redeploy.';
      case 'getRolePermissions':
      case 'setRolePermissions':
        return 'The deployed Apps Script does not support role permissions yet. Update it with the current Code.gs, run setupAccountPortal in the bound project, deploy a new web-app version, and make sure this app uses that deployment URL.';
      case 'updateMyProfile':
        return 'The deployed Apps Script does not support profile editing yet. Update it with the current Code.gs and deploy a new web-app version.';
      default:
        return 'The deployed Apps Script does not support the "$action" action. Update Code.gs and deploy a new web-app version.';
    }
  }

  Future<AuthSession> login(
    String identifier,
    String password, {
    String loginType = 'staff',
  }) async {
    if (loginType != 'staff' && loginType != 'member') {
      throw const ApiException('Select a valid account type to sign in.');
    }
    final normalizedIdentifier = identifier.trim();
    final data = await _request(
      {
        'action': 'login',
        'identifier': normalizedIdentifier,
        // Keep `email` for compatibility with Apps Script deployments that
        // have not yet been updated to read the identifier field.
        'email': normalizedIdentifier,
        'password': password,
        'loginType': loginType,
      },
      authenticationAction: true,
    );
    if (data is! Map || data['user'] is! Map) {
      throw const ApiException(
        'The server returned an invalid login response. Expected a session token and user.',
      );
    }

    final user = data['user'] as Map;
    final token = data['token']?.toString() ?? '';
    final userId = user['id']?.toString() ?? '';
    if (data['status'] != 'success' ||
        token.isEmpty ||
        userId.isEmpty ||
        user['email'] == null ||
        user['role'] == null) {
      throw const ApiException(
        'The server returned an invalid login response.',
      );
    }
    final role = user['role'].toString();
    final normalizedRole = role.toLowerCase();
    final isMember = normalizedRole == 'member';
    final isStaff = normalizedRole == 'admin' || normalizedRole == 'collector';
    if ((loginType == 'member' && !isMember) ||
        (loginType == 'staff' && !isStaff)) {
      throw ApiException(
        loginType == 'member'
            ? 'This login is for Member accounts. Choose Admin / Collector login instead.'
            : 'This login is for Admin and Collector accounts. Choose Member login instead.',
      );
    }
    return AuthSession(
      token: token,
      userId: userId,
      name: user['name']?.toString() ?? '',
      email: user['email'].toString(),
      role: role,
      accountNumber: user['accountNo']?.toString() ?? '',
      profileImageUrl: user['profileImageUrl']?.toString() ?? '',
      permissions: data['permissions'] is Map
          ? (data['permissions'] as Map).map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : const {},
      reportAccess: data['reportAccess'] is Map
          ? (data['reportAccess'] as Map).map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : const {
              'daily': true,
              'weekly': true,
              'monthly': true,
            },
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final data = await _request(
      {
        'action': 'register',
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
      },
      authenticationAction: true,
    );
    if (data is! Map || data['status'] != 'success') {
      throw const ApiException(
        'The server did not confirm registration. Please try again.',
      );
    }
  }

  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    final data = await _request({
      'action': action,
      'token': session.token,
    });
    if (data is! List) {
      throw ApiException('The server returned invalid data for $action.');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchDepositAccounts({
    required String product,
    required String cadence,
    required AuthSession session,
  }) async {
    final data = await _request({
      'action': 'getDepositAccounts',
      'token': session.token,
      'product': product,
      'cadence': cadence,
    });
    if (data is! List || data.any((record) => record is! Map)) {
      throw const ApiException(
        'The server returned invalid deposit account data.',
      );
    }
    return data
        .map((record) => Map<String, dynamic>.from(record as Map))
        .toList();
  }

  Future<Map<String, Map<String, bool>>> fetchRolePermissions(
    AuthSession session,
  ) async {
    final data = await _request({
      'action': 'getRolePermissions',
      'token': session.token,
    });
    if (data is! Map || data['permissions'] is! Map) {
      throw const ApiException(
        'The server returned invalid role permission settings.',
      );
    }
    final roles = data['permissions'] as Map;
    final result = <String, Map<String, bool>>{};
    for (final role in ['Collector', 'Member']) {
      final settings = roles[role];
      if (settings is! Map) {
        throw ApiException('The server returned invalid settings for $role.');
      }
      result[role] = {
        for (final permission in [
          'shared_data_read',
          'own_collection_read',
          'collection_manage',
          'deposit_view',
          'deposit_manage',
          'ledger_manage',
          'user_manage',
        ])
          if (settings[permission] is bool)
            permission: settings[permission] as bool,
      };
      if (result[role]!.length != 7) {
        throw ApiException(
            'The server returned incomplete settings for $role.');
      }
    }
    return result;
  }

  Future<void> saveRolePermissions(
    Map<String, Map<String, bool>> permissions,
    AuthSession session,
  ) async {
    final saved = await sendPostRequest({
      'action': 'setRolePermissions',
      'permissions': permissions,
    }, session);
    if (!saved) {
      throw const ApiException('The server did not save role permissions.');
    }
  }

  Future<void> updateMyProfile({
    required AuthSession session,
    required String name,
    required String email,
    required bool profileImageChanged,
    String? profileImageData,
    String? profileImageMimeType,
  }) async {
    final saved = await sendPostRequest({
      'action': 'updateMyProfile',
      'name': name.trim(),
      'email': email.trim(),
      if (profileImageChanged) 'profileImageChanged': true,
      if (profileImageData != null) ...{
        'profileImageData': profileImageData,
        'profileImageMimeType': profileImageMimeType,
      },
    }, session);
    if (!saved) {
      throw const ApiException('The server did not update your profile.');
    }
  }

  Future<bool> sendPostRequest(
    Map<String, dynamic> body,
    AuthSession session,
  ) async {
    final data = await _request({...body, 'token': session.token});
    return data is Map &&
        (data['status'] == 'success' || data['success'] == true);
  }
}
