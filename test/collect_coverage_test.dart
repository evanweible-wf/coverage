//TODO: copyright

library coverage.test.collect_coverage_test;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unittest/unittest.dart';

final _sampleAppPath = p.join('test', 'test_files', 'test_app.dart');
final _collectAppPath = p.join('bin', 'collect_coverage.dart');

const _timeout = const Duration(seconds: 5);

void main() {
  test('the basics', () async {
    expect(await FileSystemEntity.isFile(_sampleAppPath), isTrue);

    // need to find an open port
    var socket = await ServerSocket.bind(InternetAddress.ANY_IP_V4, 0);
    int openPort = socket.port;
    await socket.close();

    // run the sample app, with the right flags
    var sampleProcFuture = Process
        .run('dart', [
      '--enable-vm-service=$openPort',
      '--pause_isolates_on_exit',
      _sampleAppPath
    ])
        .timeout(_timeout, onTimeout: () {
      throw 'We timed out waiting for the sample app to finish.';
    });

    // run the tool with the right flags
    // TODO: need to get all of this functionality in the lib
    var toolResult = await Process
        .run('dart', [
      _collectAppPath,
      '--port',
      openPort.toString(),
      '--resume-isolates',
      '--resume-isolates'
    ])
        .timeout(_timeout, onTimeout: () {
      throw 'We timed out waiting for the tool to finish.';
    });

    expect(toolResult.exitCode, 0);

    // analyze the output json
    var json = JSON.decode(toolResult.stdout) as Map;

    expect(json.keys, unorderedEquals(['type', 'coverage']));

    await sampleProcFuture;

    // delete the temp json
  });
}