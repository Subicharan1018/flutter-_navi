// TEST-2: Unit tests for the typed AppException hierarchy.
//
// Verifies that each subtype:
//   • Is an instance of AppException (Liskov / sealed class)
//   • Exposes the correct message
//   • Can be distinguished from other subtypes at runtime
//   • toString() returns the human-readable message (not "Instance of ...")

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/app_exception.dart';

void main() {
  // --------------------------------------------------------------------------
  // NetworkException
  // --------------------------------------------------------------------------

  group('NetworkException', () {
    test('is an AppException', () {
      expect(const NetworkException(), isA<AppException>());
    });

    test('uses default message', () {
      expect(const NetworkException().message, 'No internet connection');
    });

    test('accepts custom message', () {
      const e = NetworkException('DNS failure');
      expect(e.message, 'DNS failure');
    });

    test('toString() returns message', () {
      expect(const NetworkException().toString(), 'No internet connection');
    });
  });

  // --------------------------------------------------------------------------
  // AuthException
  // --------------------------------------------------------------------------

  group('AuthException', () {
    test('is an AppException', () {
      expect(const AuthException(), isA<AppException>());
    });

    test('uses default message', () {
      expect(const AuthException().message, 'Invalid username or password');
    });

    test('accepts custom message', () {
      const e = AuthException('Token expired');
      expect(e.message, 'Token expired');
    });

    test('is NOT a NetworkException', () {
      expect(const AuthException(), isNot(isA<NetworkException>()));
    });
  });

  // --------------------------------------------------------------------------
  // ServerException
  // --------------------------------------------------------------------------

  group('ServerException', () {
    test('is an AppException', () {
      expect(ServerException(500), isA<AppException>());
    });

    test('includes status code in message', () {
      expect(ServerException(503).message, contains('503'));
    });

    test('exposes statusCode field', () {
      expect(ServerException(503).statusCode, 503);
    });

    test('toString() returns message', () {
      expect(ServerException(500).toString(), 'Server error (500)');
    });
  });

  // --------------------------------------------------------------------------
  // TimeoutException
  // --------------------------------------------------------------------------

  group('TimeoutException', () {
    test('is an AppException', () {
      expect(const TimeoutException(), isA<AppException>());
    });

    test('uses default message', () {
      expect(const TimeoutException().message, 'Request timed out');
    });

    test('is NOT a NetworkException', () {
      expect(const TimeoutException(), isNot(isA<NetworkException>()));
    });
  });

  // --------------------------------------------------------------------------
  // SubsonicApiException
  // --------------------------------------------------------------------------

  group('SubsonicApiException', () {
    test('is an AppException', () {
      expect(
        SubsonicApiException(10, 'Required parameter missing'),
        isA<AppException>(),
      );
    });

    test('exposes code field', () {
      expect(SubsonicApiException(10, 'desc').code, 10);
    });

    test('includes code and description in message', () {
      final e = SubsonicApiException(40, 'Wrong username or password');
      expect(e.message, contains('40'));
      expect(e.message, contains('Wrong username or password'));
    });

    test('toString() returns human-readable message', () {
      final e = SubsonicApiException(10, 'Required parameter missing');
      expect(e.toString(), 'Subsonic error 10: Required parameter missing');
    });
  });

  // --------------------------------------------------------------------------
  // Pattern matching (sealed class exhaustiveness)
  // --------------------------------------------------------------------------

  group('AppException pattern matching', () {
    String classify(AppException e) => switch (e) {
      NetworkException() => 'network',
      AuthException() => 'auth',
      ServerException() => 'server',
      TimeoutException() => 'timeout',
      SubsonicApiException() => 'subsonic',
    };

    test('NetworkException classified correctly', () {
      expect(classify(const NetworkException()), 'network');
    });

    test('AuthException classified correctly', () {
      expect(classify(const AuthException()), 'auth');
    });

    test('ServerException classified correctly', () {
      expect(classify(ServerException(500)), 'server');
    });

    test('TimeoutException classified correctly', () {
      expect(classify(const TimeoutException()), 'timeout');
    });

    test('SubsonicApiException classified correctly', () {
      expect(classify(SubsonicApiException(10, 'desc')), 'subsonic');
    });
  });

  // --------------------------------------------------------------------------
  // Throw / catch interop (confirms they are throwable)
  // --------------------------------------------------------------------------

  group('AppException throw/catch', () {
    test('NetworkException can be thrown and caught as AppException', () {
      expect(
        () => throw const NetworkException(),
        throwsA(isA<AppException>()),
      );
    });

    test('AuthException can be caught as AppException', () {
      expect(() => throw const AuthException(), throwsA(isA<AppException>()));
    });

    test('ServerException can be caught specifically', () {
      expect(() => throw ServerException(503), throwsA(isA<ServerException>()));
    });

    test('NetworkException is NOT caught as AuthException', () {
      expect(
        () => throw const NetworkException(),
        isNot(throwsA(isA<AuthException>())),
      );
    });
  });
}
