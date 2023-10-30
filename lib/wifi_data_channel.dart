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
  final int port = 62526;
  Socket? client;

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
        final socket = await Socket.connect(data.address, port,
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
    client!.listen((event) {
      debugPrint("RECEIVED SOMETHING BOSS");
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

    final server = await ServerSocket.bind(address, port);
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
  }

  @override
  Future<void> sendChunk(FileChunk chunk) async {
    client!.write(chunk.data);
  }

  /// Returns the Wi-Fi hotspot IP address of the current device.
  ///
  /// This methods accepts a [oldInterfaces] list of interfaces that was saved
  /// in memory *before* turning the Wi-Fi hotspot on, supposedly helping in
  /// finding the newly created network interface.
  ///
  /// This will throw an error if the [oldInterfaces] argument is not provided
  /// and several private class IPs are present in [interfaces].
  InternetAddress retrieveHotspotIPAddress(List<NetworkInterface> interfaces,
      {List<NetworkInterface>? oldInterfaces}) {
    if (interfaces.isEmpty) {
      throw ArgumentError(
          'Cannot retrieve hotspot address from an empty interfaces list.');
    }

    // Debug log
    debugPrint("Input interfaces: $interfaces");
    if (oldInterfaces != null) {
      debugPrint("Input old interfaces: $oldInterfaces");
    } else {
      debugPrint("No old interfaces provided.");
    }

    // Retrieve all private addresses
    List<InternetAddress> privateAddresses = [];
    for (NetworkInterface ni in interfaces) {
      privateAddresses.addAll(ni.addresses.where((address) {
        List<String> words = address.address.split(".");

        // Class A
        if (words[0] == "10") return true;
        // Class B
        int second = int.parse(words[1]);
        if (words[0] == "172" && second >= 16 && second <= 31) return true;
        // Class C
        if (words[0] == "192" && words[1] == "168") return true;

        return false;
      }).toList());
    }

    // If there's only one private address, return it
    if (privateAddresses.length == 1) {
      return privateAddresses.first;
    }
    // Throw if there are no private addresses
    if (privateAddresses.isEmpty) {
      throw StateError('No private address was found.');
    }

    // If there are several private interfaces, we need to use [oldInterfaces]
    // list to find out which one appeared when the hotspot was turned on.
    if (oldInterfaces != null) {
      List<InternetAddress> matching = privateAddresses.where((address) {
        return oldInterfaces.where((interface) {
          return interface.addresses.contains(address);
        }).isEmpty;
      }).toList();

      if (matching.length == 1) {
        return matching.first;
      } else {
        throw StateError(
            'Several compatible private IP addresses appeared, cannot choose between them.\nPotential candidates: $matching');
      }
    }

    throw StateError(
        "Could not retrieve hotspot IP address from provided information.");
  }

  @override
  Future<void> close() async {
    if (client != null) {
      client!.close();
    }
  }
}
