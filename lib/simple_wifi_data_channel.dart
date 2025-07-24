library wifi_data_channel;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/metadata/channel_metadata.dart';
import 'package:venice_core/channels/events/data_channel_event.dart';
import 'package:flutter/foundation.dart';
import 'package:venice_core/network/message.dart';
import 'package:venice_core/protobuf/venice.pb.dart';
import 'package:wifi_data_channel/exception/wifi_connection_exception.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'exception/wrong_wifi_connection_exception.dart';



class SimpleWifiDataChannel extends DataChannel {
  SimpleWifiDataChannel(super.identifier);
  final int port = 62526;
  Socket? client;
  bool useProtoBuf = true;

  static const platform = MethodChannel('wifi/connect');

  @override
  Future<void> initReceiver(ChannelMetadata data) async {



    if (await WiFiForIoTPlugin.isConnected() == false) {
      WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: true);

      bool connected = await connectToRegisteredNetwork(data.apIdentifier);

      if (!connected) {
        throw WifiConnectionException(
            'Unable to connect to ${data.apIdentifier} network');
      }
    }
    else if(await WiFiForIoTPlugin.getSSID() != data.apIdentifier)
    {
      throw WrongWifiConnectionException(
          'You need to connect to ${data.apIdentifier} network');
    }


    debugPrint("[SimpleWifiChannel] Connected to the ${data.apIdentifier} network");



    // Opening data connection with host.
    bool connected = false;
    int fileSize = 0;
    while (!connected) {
      try {
        debugPrint('[SimpleWifiChannel] Connecting to: ${data.address}:${data.port}');
        final socket = await Socket.connect(data.address, data.port,
            timeout: const Duration(seconds: 5));
        debugPrint(
            '[SimpleWifiChannel] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        client = socket;
        connected = true;
        //Uint8List? fileSizebytes = client!.read();

        /*if(fileSizebytes != null)
          {
            fileSize = int.parse(utf8.decode(fileSizebytes).trim());
          }*/


      } catch (err) {
        debugPrint("[SimpleWifiChannel] Failed to connect to host, retrying...");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Reception listener
    //BytesBuilder builder = BytesBuilder();

    client!.listen((data) async{
      VeniceMessage msg;

      if(!useProtoBuf) {
        final jsonString = String.fromCharCodes(data); // Decode bytes to string
        debugPrint("==> MESSAGE RECEIVED $jsonString");
        msg = VeniceMessage.fromJson(jsonString);
      }
      else {
        final msgProto = VeniceMessageProto.fromBuffer(data);
        msg = VeniceMessage.fromProtoBuf(msgProto);
      }

      try {
        int msgId = msg.messageId;
        debugPrint("==> MESSAGE #$msgId COMPLETE");
        on(DataChannelEvent.data, msg);
        debugPrint("==> Sending acknowledgement");
        client!.write(VeniceMessage.acknowledgement(msgId).toJson());
        await client!.flush();
        debugPrint("==> Acknowledgement sent");
      } catch (e) {
        debugPrint("==> MESSAGE NOT COMPLETE, WAITING FOR NEXT DATA");
      }
    });
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    if (await WiFiForIoTPlugin.isConnected()) {
      //await WiFiForIoTPlugin.isdisconnect();
      //}

      /*List<NetworkInterface> interfacesBeforeActivation =
    await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4);*/

      /*bool result = await WiFForIoTPlugin.setWiFiAPEnabled(true);
      debugPrint("WiFi AP activation successful: $result");*/
      InternetAddress? address;
      String ssid = (await WiFiForIoTPlugin.getSSID())!;
      String ip = (await WiFiForIoTPlugin.getIP())!;

      List<NetworkInterface> interfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: false,
          type: InternetAddressType.IPv4);

      for (var interface in interfaces) {
        for (var current_address in interface.addresses) {
          if (current_address.address == ip) {
            address = current_address;
            break;
          }
        }
      }

      if (address == null)
        throw WifiConnectionException(
            'You need to be connected to a Wifi Network');

      debugPrint("[SimpleWifiChannel] Sender successfully initialized.");
      debugPrint("[SimpleWifiChannel]     IP: $ip");
      debugPrint("[SimpleWifiChannel]     SSID: $ssid");

      final server = await ServerSocket.bind(address, port);
      server.listen((clientSocket) {
        debugPrint(
            '[SimpleWifiChannel] Connection from ${clientSocket.remoteAddress
                .address}:${clientSocket.remotePort}');
        client = clientSocket;
      });

      // Send socket information to client.
      debugPrint("[SimpleWifiChannel] Sending Channel Metadata to client..");
      await channel.sendChannelMetadata(
          ChannelMetadata(super.identifier, address.address, ssid, '', port));

      // Waiting for client connection.
      while (client == null) {

        debugPrint("[SimpleWifiChannel] Waiting for client to connect...");
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Listen for acknowledgements
      client!.listen((data) {
        VeniceMessage ackMsg;
        if (!useProtoBuf) {
          final jsonString = String.fromCharCodes(
              data); // Decode bytes to string
          final jsonData = jsonDecode(jsonString); // Convert string to JSON
          ackMsg = VeniceMessage.fromJson(jsonData);
        }
        else {
          final msgProto = VeniceMessageProto.fromBuffer(data);
          ackMsg = VeniceMessage.fromProtoBuf(msgProto);
        }
        on(DataChannelEvent.acknowledgment, ackMsg.messageId);
      });
    }
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

  Future<bool> connectToRegisteredNetwork(String ssid) async {
    bool connected = false;
    try {
      final String result = await platform.invokeMethod('connectToRegisteredNetwork', {'ssid': ssid});
      debugPrint(result);
      if(result.contains("Connected to")){
        connected = true;
      }

    } on PlatformException catch (e) {
      debugPrint("Failed to connect: ${e.message}");
    }

    return connected;
  }

}
