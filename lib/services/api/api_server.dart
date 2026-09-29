import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_action.dart';
import 'api_openapi.dart';
import 'api_protocol.dart';
import 'api_schema.dart';
import 'api_token.dart';

class ApiServer {
  ApiServer({required this.registry, this.port = 9876});

  final ApiActionRegistry registry;
  int port;

  HttpServer? _server;

  bool get isRunning => _server != null;

  String get baseUrl => 'http://127.0.0.1:$port';

  Future<bool> start({int? port}) async {
    if (port != null) this.port = port;
    await stop();
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, this.port);
      _server = server;
      server.listen(_handle, onError: (Object _) {});
      return true;
    } on SocketException {
      _server = null;
      return false;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  void dispose() {
    unawaited(stop());
  }

  static Future<List<String>> lanAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in interfaces) {
        for (final a in i.addresses) {
          out.add(a.address);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _handle(HttpRequest request) async {
    _applyCors(request);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/' || path == '/health') {
      await _send(request, 200, {
        'ok': true,
        'name': 'clicker',
        'version': apiVersion,
        'authRequired': true,
        'capabilities': registry.length,
        'mcp': '/mcp',
        'openapi': '/openapi.json',
      });
      return;
    }

    if (!_authorized(request)) {
      await _send(request, 401, {
        'ok': false,
        'error': {
          'code': 'unauthorized',
          'message': '缺少或无效的访问令牌',
          'hint': '在请求头加 Authorization: Bearer <token>；'
              '令牌可在软件「外部接口」设置页查看',
        },
      });
      return;
    }

    try {
      if (path == '/mcp') {
        if (request.method != 'POST') {
          await _send(request, 405, {
            'ok': false,
            'error': {
              'code': 'method_not_allowed',
              'message': 'MCP 端点仅支持 POST',
            },
          });
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        final result = await handleMcpHttp(registry, body);
        if (result.body == null) {
          request.response.statusCode = result.status;
          await request.response.close();
          return;
        }
        await _send(request, result.status, result.body);
        return;
      }

      if (path == '/openapi.json') {
        await _send(
          request,
          200,
          buildOpenApiDocument(registry, baseUrl: baseUrl),
        );
        return;
      }

      if (path == '/api/v1/capabilities') {
        await _send(request, 200, {
          'ok': true,
          'apiVersion': apiVersion,
          'count': registry.length,
          'groups': registry.groups,
          'actions': [for (final a in registry.all) a.toDescriptorJson()],
        });
        return;
      }

      if (path.startsWith('/api/v1/')) {
        final name = path.substring('/api/v1/'.length);
        final args = await _readArgs(request);
        final result = await handleRestCall(registry, name, args);
        await _send(request, result.status, result.body);
        return;
      }

      await _send(request, 404, {
        'ok': false,
        'error': {
          'code': 'not_found',
          'message': '未知路径 $path',
          'hint': '可用端点：/health、/mcp、/openapi.json、'
              '/api/v1/capabilities、/api/v1/<能力名>',
        },
      });
    } on ApiError catch (e) {
      final status = switch (e.code) {
        'not_found' => 404,
        'conflict' => 409,
        'unsupported' => 501,
        _ => 400,
      };
      await _send(request, status, {'ok': false, 'error': e.toJson()});
    } catch (e) {
      await _send(request, 500, {
        'ok': false,
        'error': {'code': 'internal', 'message': e.toString()},
      });
    }
  }

  Future<Map<String, dynamic>> _readArgs(HttpRequest request) async {
    if (request.method == 'GET') {
      return request.uri.queryParameters.map((k, v) => MapEntry(k, v));
    }
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) return <String, dynamic>{};
    final map = asMap(jsonDecode(body));
    if (map == null) {
      throw ApiError.invalidArgument('请求体必须是 JSON 对象',
          hint: '例如：{"x": 100, "y": 200}');
    }
    return map;
  }

  bool _authorized(HttpRequest request) {
    if (ApiToken.current.isEmpty) return false;

    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header != null) {
      final value = header.trim();
      if (value.toLowerCase().startsWith('bearer ')) {
        if (ApiToken.verify(value.substring(7).trim())) return true;
      } else if (ApiToken.verify(value)) {
        return true;
      }
    }

    final xToken = request.headers.value('x-api-token');
    if (xToken != null && ApiToken.verify(xToken.trim())) return true;

    final query = request.uri.queryParameters['token'];
    if (query != null && ApiToken.verify(query)) return true;

    return false;
  }

  void _applyCors(HttpRequest request) {
    final headers = request.response.headers;
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Access-Control-Allow-Headers',
        'Authorization, Content-Type, X-Api-Token');
    headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    headers.set('Access-Control-Max-Age', '86400');
  }

  Future<void> _send(HttpRequest request, int status, Object? body) async {
    request.response.statusCode = status;
    request.response.headers
        .set('Content-Type', 'application/json; charset=utf-8');
    if (body != null) request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
