library wifi_data_channel;

import 'dart:io';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/metadata/channel_metadata.dart';
import 'package:venice_core/channels/events/data_channel_event.dart';
import 'package:flutter/foundation.dart';
import 'package:venice_core/network/message.dart';
import 'package:wifi_data_channel/access_point_utils.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);
  final int port = 62526;
  RawSocket? client;

  @override
  Future<void> initReceiver(ChannelMetadata data) async {
    // Enable Wi-Fi scanning.
    if ((await WiFiForIoTPlugin.isConnected()) == false) {
      WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: true);
    }
    CanGetScannedResults check =
        await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    debugPrint("Can get AP scan results: ${check.name}");
    await WiFiScan.instance.startScan();

    // Loop until we find matching AP.
    WiFiAccessPoint? accessPoint;
    while (accessPoint == null) {
      await WiFiScan.instance.startScan();
      List<WiFiAccessPoint> results =
          await WiFiScan.instance.getScannedResults();
      Iterable<WiFiAccessPoint> matching =
          results.where((element) => element.ssid == data.apIdentifier);

      if (matching.isNotEmpty) {
        accessPoint = matching.first;
      } else {
        await Future.delayed(const Duration(seconds: 1));
        debugPrint("[WifiChannel] No matching AP, rescanning...");
      }
    }

    // Connection to access point.
    await WiFiForIoTPlugin.setEnabled(true);
    bool connected = false;
    while (!connected) {
      debugPrint("[WifiChannel] Connecting to AP...");
      connected = await WiFiForIoTPlugin.findAndConnect(data.apIdentifier,
          password: data.password, withInternet: true);
      await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint("[WifiChannel] Connected to AP.");

    // Opening data connection with host.
    connected = false;
    while (!connected) {
      try {
        debugPrint('[WifiChannel] Connecting to: ${data.address}:$port');
        final socket = await RawSocket.connect(data.address, port,
            timeout: const Duration(seconds: 5));
        debugPrint(
            '[WifiChannel] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        client = socket;
        connected = true;
      } catch (err) {
        debugPrint("[WifiChannel] Failed to connect to host, retrying...");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Reception listener
    BytesBuilder builder = BytesBuilder();

    client!.listen((event) {
      if (event == RawSocketEvent.read) {
        Uint8List? bytes = client!.read();
        if (bytes != null) {
          builder.add(bytes);

          // Expecting errors here
          VeniceMessage msg;
          try {
            msg = VeniceMessage.fromBytes(builder.toBytes());
            int msgId = msg.messageId;
            debugPrint("==> MESSAGE #$msgId COMPLETE");
            on(DataChannelEvent.data, msg);
            builder.clear();
            client!.write(VeniceMessage.acknowledgement(msgId).toBytes());
          } catch (e) {
            // debugPrint("==> MESSAGE NOT COMPLETE, WAITING FOR NEXT DATA");
          }
        }
      }
    });
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    if (await WiFiForIoTPlugin.isEnabled()) {
      await WiFiForIoTPlugin.disconnect();
    }

    List<NetworkInterface> interfacesBeforeActivation =
        await NetworkInterface.list(
            includeLoopback: false,
            includeLinkLocal: false,
            type: InternetAddressType.IPv4);

    bool result = await WiFiForIoTPlugin.setWiFiAPEnabled(true);
    debugPrint("WiFi AP activation successful: $result");

    List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4);

    InternetAddress address = retrieveHotspotIPAddress(interfaces,
        oldInterfaces: interfacesBeforeActivation);
    String ssid = (await WiFiForIoTPlugin.getWiFiAPSSID())!;
    String key = (await WiFiForIoTPlugin.getWiFiAPPreSharedKey())!;

    debugPrint("[WifiChannel] Sender successfully initialized.");
    debugPrint("[WifiChannel]     IP: ${address.address}");
    debugPrint("[WifiChannel]     SSID: $ssid");
    debugPrint("[WifiChannel]     Key: $key");

    final server = await RawServerSocket.bind(address, port);
    server.listen((clientSocket) {
      debugPrint(
          '[WifiChannel] Connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
      client = clientSocket;
    });

    // Send socket information to client.
    await channel.sendChannelMetadata(
        ChannelMetadata(super.identifier, address.address, ssid, key));

    // Waiting for client connection.
    while (client == null) {
      debugPrint("[WifiChannel] Waiting for client to connect...");
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Listen for acknowledgements
    client!.listen((event) {
      debugPrint(event.toString());
      if (event == RawSocketEvent.read) {
        Uint8List? bytes = client!.read();
        if (bytes != null) {
          VeniceMessage ackMsg = VeniceMessage.fromBytes(bytes);
          on(DataChannelEvent.acknowledgment, ackMsg.messageId);
        }
      }
    });
  }

  @override
  Future<void> sendMessage(VeniceMessage chunk) async {
    client!.write(chunk.toBytes());
  }

  @override
  Future<void> close() async {
    if (client != null) {
      client!.close();
    }
  }
}
