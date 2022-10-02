library wifi_data_channel;

import 'dart:io';

import 'package:channel_multiplexed_scheduler/channels/abstractions/bootstrap_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/abstractions/data_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/channel_metadata.dart';
import 'package:channel_multiplexed_scheduler/file/file_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';


class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);
  Socket? client;

  @override
  Future<void> initReceiver(ChannelMetadata data) async {
    debugPrint("GOT METADATA: $data");

    // Enable Wi-Fi scanning.
    await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    await WiFiScan.instance.startScan();

    // Loop until we find matching AP.
    WiFiAccessPoint? accessPoint;
    while (accessPoint == null) {
      List<WiFiAccessPoint> results = await WiFiScan.instance.getScannedResults();
      Iterable<WiFiAccessPoint> matching = results.where((element) => element.ssid == data.apIdentifier);

      if (matching.isNotEmpty) {
        accessPoint = matching.first;
      } else {
        await Future.delayed(const Duration(seconds: 1));
        debugPrint("No matching AP, rescanning...");
      }
    }
    throw UnimplementedError();
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    await WiFiForIoTPlugin.setWiFiAPEnabled(true);

    String address = (await WiFiForIoTPlugin.getIP())!;
    String ssid = (await WiFiForIoTPlugin.getWiFiAPSSID())!;
    String key = (await WiFiForIoTPlugin.getWiFiAPPreSharedKey())!;

    debugPrint("[WifiChannel] Sender successfully initialized.");
    debugPrint("[WifiChannel]     IP: $address");
    debugPrint("[WifiChannel]     SSID: $ssid");
    debugPrint("[WifiChannel]     Key: $key");

    final server = await ServerSocket.bind(address, 8080);
    server.listen((clientSocket) {
      debugPrint('Connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
      client = clientSocket;
    });

    // Send socket information to client.
    await channel.sendChannelMetadata(ChannelMetadata(super.identifier, address, ssid, key));

    // Waiting for client connection.
    while(client == null) {
      debugPrint("[WifiChannel] Waiting for client to connect...");
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<void> sendChunk(FileChunk chunk) {
    // TODO: implement sendChunk
    throw UnimplementedError();
  }
}