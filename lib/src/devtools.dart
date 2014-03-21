// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage.src.devtools;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:io';
import 'package:http/http.dart' as http;

class IsolateInfo {
  final _Connection _connection;
  final String name;
  IsolateInfo(this._connection, Map json) :
    name = json['name'];

  Future<Map> getCoverage() =>
      _connection.request('isolates/$name/coverage')
      .then((resp) => resp['coverage']);

  Future resume() => _connection.request('isolates/$name/resume');
}

/// Interface to Dart's VM Observatory
class Observatory {
  final _Connection _connection;

  Observatory._(this._connection);

  static Future<Observatory> connect(String host, String port) {
    var uri = 'http://$host:$port';
    var observatory = new Observatory._(new _VmConnection(uri));
    return new Future.value(observatory);
  }

  static Future<Observatory> connectOverDevtools(String host, String port) {
    var uri = 'http://$host:$port/json';
    return _DevtoolsConnection.connect(uri).then((c) => new Observatory._(c));
  }

  Future<Iterable<IsolateInfo>> getIsolates() =>
      _connection.request('isolates')
      .then((resp) => resp['members'])
      .then((members) => (members == null) ? [] : members)
      .then((members) => members.map((m) => new IsolateInfo(_connection, m)));

  Future unpin(String isolateId) =>
      _connection.request('isolates/$isolateId/unpin');

  Future close() => _connection.close();
}

/// Dart Observatory connection
abstract class _Connection {
  Future<Map> request(String request);
  Future close();
}

/// Observatory connection over HTTP GET requests
class _VmConnection implements _Connection {
  final String uri;

  _VmConnection(this.uri);

  Future<Map> request(String request) {
    return http.get('$uri/$request')
        .then((resp) => resp.body)
        .then((resp) => resp.isEmpty ? {} : JSON.decode(resp));
  }

  Future close() => new Future.value();
}

/// Observatory connection over Chrome DevTools websocket
class _DevtoolsConnection implements _Connection {
  final WebSocket _socket;
  final Map<int, Completer> _pendingRequests = {};
  int _requestId = 1;

  _DevtoolsConnection(this._socket) {
    _socket.listen(_handleResponse);
  }

  static Future<_Connection> connect(String uri) {
    _getWebsocketDebuggerUrl(response) {
      var json = JSON.decode(response.body);
      if (json.length < 1) throw new StateError('No open pages');
      if (json.length > 1) {
        throw new UnsupportedError('Multiple page support not yet implemented');
      }
      var pageData = json[0];
      var debuggerUrl = pageData['webSocketDebuggerUrl'];
      if (debuggerUrl == null) {
        throw new StateError('Unable to obtain debugger URL');
      }
      return debuggerUrl;
    }

    return http.get(uri).then((response) {
      var webSocketDebuggerUrl = _getWebsocketDebuggerUrl(response);
      return WebSocket.connect(webSocketDebuggerUrl)
          .then((socket) => new _DevtoolsConnection(socket));
    });
  }

  @override
  Future<Map> request(String request) {
    _pendingRequests[_requestId] = new Completer();
    _socket.add(JSON.encode({
      'id': _requestId,
      'method': 'Dart.observatoryQuery',
      'params': {
        'id': '$_requestId',
        'query': request,
      },
    }));
    return _pendingRequests[_requestId++].future;
  }

  Future close() => _socket.close();

  void _handleResponse(String response) {
    var json = JSON.decode(response);
    if (json['method'] == 'Dart.observatoryData') {
      var id = int.parse(json['params']['id']);
      var message = JSON.decode(json['params']['data']);
      _pendingRequests.remove(id).complete(message);
    }
  }
}
