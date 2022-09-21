library wifi_data_channel;

import 'dart:io';

import 'package:channel_multiplexed_scheduler/channels/abstractions/bootstrap_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/abstractions/data_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/channel_metadata.dart';
import 'package:channel_multiplexed_scheduler/file/file_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';


class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);

  @override
  Future<void> initReceiver(ChannelMetadata data) {
    // TODO: implement initReceiver
    throw UnimplementedError();
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    await WiFiForIoTPlugin.setWiFiAPEnabled(true);
    debugPrint("[WifiChannel] Sender successfully initialized.");
    debugPrint("[WifiChannel]     IP: ${await WiFiForIoTPlugin.getIP()}");
    debugPrint("[WifiChannel]     SSID: ${await WiFiForIoTPlugin.getWiFiAPSSID()}");
    debugPrint("[WifiChannel]     Key: ${await WiFiForIoTPlugin.getWiFiAPPreSharedKey()}");
  }

  @override
  Future<void> sendChunk(FileChunk chunk) {
    // TODO: implement sendChunk
    throw UnimplementedError();
  }
}