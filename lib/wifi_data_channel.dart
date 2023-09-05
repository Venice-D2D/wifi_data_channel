library wifi_data_channel;

import 'dart:io';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/channels/channel_metadata.dart';
import 'package:venice_core/file/file_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';


class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);
  Socket? client;

  @override
  Future<void> initReceiver(ChannelMetadata data) async {
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
        debugPrint("[WifiChannel] No matching AP, rescanning...");
      }
    }

    // Connection to access point.
    await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: true);
    bool connected = false;
    while (!connected) {
      debugPrint("[WifiChannel] Connecting to AP...");
      connected = await WiFiForIoTPlugin.findAndConnect(data.apIdentifier, password: data.password);
      await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint("[WifiChannel] Connected to AP.");

    // Opening data connection with host.
    connected = false;
    while (!connected) {
      try {
        final socket = await Socket.connect(data.address, 62526);
        debugPrint('[WifiChannel] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        connected = true;
      } catch (err) {
        debugPrint("[WifiChannel] Failed to connect to host, retrying...");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw UnimplementedError();
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    if (await WiFiForIoTPlugin.isEnabled()) {
      await WiFiForIoTPlugin.disconnect();
    }
    bool result = await WiFiForIoTPlugin.setWiFiAPEnabled(true);
    debugPrint("WiFi AP activation successful: $result");
    List<NetworkInterface> firstNetInterface = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false, type: InternetAddressType.IPv4);

    String address = (await WiFiForIoTPlugin.getIP())!;
    String ssid = (await WiFiForIoTPlugin.getWiFiAPSSID())!;
    String key = (await WiFiForIoTPlugin.getWiFiAPPreSharedKey())!;

    // TODO check selected address is a local IP address
    List<NetworkInterface> secondNetInterface = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false, type: InternetAddressType.IPv4);
    List<NetworkInterface> myNetInterface = List<NetworkInterface>.empty(growable: true);
    for (var element in firstNetInterface) {
      if(!secondNetInterface.contains(element)){
        myNetInterface.add(element);
      }
    }
    address = myNetInterface.last.addresses[0].address;

    debugPrint("[WifiChannel] Sender successfully initialized.");
    debugPrint("[WifiChannel]     IP: $address");
    debugPrint("[WifiChannel]     SSID: $ssid");
    debugPrint("[WifiChannel]     Key: $key");

    final server = await ServerSocket.bind(address, 62526);
    server.listen((clientSocket) {
      debugPrint('[WifiChannel] Connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
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