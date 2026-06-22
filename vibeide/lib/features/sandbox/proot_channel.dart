import 'package:flutter/services.dart';

class ProotChannel {
  static const _ch = MethodChannel('com.vibeide/proot');

  Future<bool> isExtracted() async =>
      await _ch.invokeMethod<bool>('isExtracted') ?? false;

  Future<void> extractAlpine() async =>
      await _ch.invokeMethod<void>('extractAlpine');

  Future<void> startSandbox() async =>
      await _ch.invokeMethod<void>('startSandbox');

  Future<void> stopSandbox() async =>
      await _ch.invokeMethod<void>('stopSandbox');

  Future<bool> isSandboxRunning() async =>
      await _ch.invokeMethod<bool>('isSandboxRunning') ?? false;
}
