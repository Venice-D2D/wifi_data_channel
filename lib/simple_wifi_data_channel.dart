library wifi_data_channel;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/metadata/channel_metadata.dart';
import 'package:venice_core/channels/events/data_channel_event.dart';
import 'package:flutter/foundation.dart';
import 'package:venice_core/network/message.dart';
import 'package:venice_core/protobuf/venice.pb.dart';
import 'package:wifi_data_channel/exception/wifi_connection_exception.dart';
//import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'exception/wrong_wifi_connection_exception.dart';



class SimpleWifiDataChannel extends DataChannel {
  SimpleWifiDataChannel(super.identifier);
  final int port = 62526;
  Socket? client;
  bool useProtoBuf = true;
  ServerSocket? server;

  static const platform = MethodChannel('wifi/connect');

  @override
  Future<void> initReceiver(ChannelMetadata data) async {

    final List<ConnectivityResult> connectivityResults = await (Connectivity().checkConnectivity());

    final networkInfoManager = NetworkInfo();

    final networkName = await networkInfoManager.getWifiName();
    final bssid = await networkInfoManager.getWifiBSSID();
    final mask = await networkInfoManager.getWifiSubmask();
    final ip = await NetworkInfo().getWifiIP();
    String ipChecked = "";
    String maskChecked = "";

    if(ip!=null) {
      ipChecked = ip;
    }

    if(mask!=null) {
      maskChecked = mask;
    }


    if (!(connectivityResults.contains(ConnectivityResult.wifi))) {

      bool connected = await connectToRegisteredNetwork(data.apIdentifier);

      if (!connected) {
        throw WifiConnectionException(
            'Unable to connect to ${data.apIdentifier} network');
      }
    }
    else
    {
      int remoteNetworkInt = computeNetworkAsInt(data.address, data.apIdentifier);
      //int networkRemoteMaskLocalIP= computeNetworkAsInt(ipChecked, data.apIdentifier);
      int localNetworkInt = computeNetworkAsInt(ipChecked, maskChecked);
     // int networkLocalMaskRemoteIP = computeNetworkAsInt(data.address, maskChecked); //This value has to be correct because we are on the same network

      debugPrint('[SimpleWifiChannel] Expected BSSID: ${data.apIdentifier}');
      debugPrint('[SimpleWifiChannel] Name: $networkName');


      debugPrint('[SimpleWifiChannel] BSSID: $bssid');
      debugPrint('[SimpleWifiChannel] IP: $ip');

      debugPrint('[SimpleWifiChannel] remoteNetworkInt: $remoteNetworkInt');
      //debugPrint('[SimpleWifiChannel] networkRemoteMaskLocalIP: $networkRemoteMaskLocalIP');
      debugPrint('[SimpleWifiChannel] localNetworkInt: $localNetworkInt');
      //debugPrint('[SimpleWifiChannel] networkLocalMaskRemoteIP: $networkLocalMaskRemoteIP');

      if(localNetworkInt != remoteNetworkInt) {
        throw WrongWifiConnectionException(
            'You need to connect to ${data.apIdentifier} network');
      }


    }



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
    List<int> buffer = [];

    int messageLength = -1;

    client!.listen((data) async{

      VeniceMessage msg;

      buffer.addAll(data);

      if(data.length>=4 && messageLength ==-1 ){

        final lengthBytes = buffer.sublist(0, 4);
        messageLength = ByteData.sublistView(Uint8List.fromList(lengthBytes))
            .getUint32(0, Endian.big);
      }
      else if(buffer.length >= 4 + messageLength){

        final messageBytes = Uint8List.fromList(
          buffer.sublist(4, 4 + messageLength),
        );

        if(!useProtoBuf) {
          final jsonString = utf8.decode(messageBytes); //String.fromCharCodes(data); // Decode bytes to string
          debugPrint("==> MESSAGE RECEIVED $jsonString");
          msg = VeniceMessage.fromJson(jsonString);
        }
        else {
          final msgProto = VeniceMessageProto.fromBuffer(messageBytes);
          msg = VeniceMessage.fromProtoBuf(msgProto);
        }

        try {
          int msgId = msg.messageId;
          debugPrint("==> MESSAGE #$msgId COMPLETE");
          on(DataChannelEvent.data, msg);
          debugPrint("==> Sending acknowledgement");
          if (!useProtoBuf){
            debugPrint("==> Sending JSON Ack");
            client!.write(VeniceMessage.acknowledgement(msgId).toJson());
          }
          else {
            debugPrint("==> Sending ProtoBuf Ack");
            VeniceMessageProto messageProto = VeniceMessage.acknowledgement(msgId).toProtoBuf();
            Uint8List data = messageProto.writeToBuffer();
            client!.add(data);
            await client!.flush();
          }
          await client!.flush();
          debugPrint("==> Acknowledgement sent");
          buffer.removeRange(0, 4 + messageLength);
          messageLength = -1;
        } catch (e) {
          debugPrint("==> MESSAGE NOT COMPLETE, WAITING FOR NEXT DATA");
        }

      }




    });
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {

    final List<ConnectivityResult> connectivityResults = await (Connectivity().checkConnectivity());

    debugPrint("[SimpleWifiChannel] initSender - Results List: ${connectivityResults.toString()}");
    final networkInfoManager = NetworkInfo();
    String? ssid;
    String? submask;
    String? ip;
    InternetAddress? address;

    if (connectivityResults.contains(ConnectivityResult.wifi)) {
      //await WiFiForIoTPlugin.isdisconnect();
      //}

      /*List<NetworkInterface> interfacesBeforeActivation =
    await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4);*/

      /*bool result = await WiFForIoTPlugin.setWiFiAPEnabled(true);
      debugPrint("WiFi AP activation successful: $result");*/

      ssid = (await networkInfoManager.getWifiName())!;
      submask = (await networkInfoManager.getWifiSubmask())!;
      String? bssid = (await networkInfoManager.getWifiBSSID())!;
      String? gatewayIp = (await networkInfoManager.getWifiGatewayIP())!;

      ip = (await networkInfoManager.getWifiIP())!;



      debugPrint("[SimpleWifiChannel] Sender successfully initialized.");
      debugPrint("[SimpleWifiChannel]     IP: $ip");
      debugPrint("[SimpleWifiChannel]     SSID: $ssid");
      debugPrint("[SimpleWifiChannel]     BSSID: $bssid");
      debugPrint("[SimpleWifiChannel]     Gateway: $gatewayIp");
      debugPrint("[SimpleWifiChannel]     Submask: $submask");



      //unawaited(dealWithClientConnections(server));

      // Waiting for client connection.
      /*while (client == null) {

        debugPrint("[SimpleWifiChannel] Waiting for client to connect...");
        await Future.delayed(const Duration(milliseconds: 500));
      }*/

      // Listen for acknowledgements
     /*client!.listen((data) {
        VeniceMessage ackMsg;
        if (!useProtoBuf) {
          final jsonString = String.fromCharCodes(
              data); // Decode bytes to string
          debugPrint("[SimpleWifiChannel] JSON String Received: "+jsonString);
          debugPrint("[SimpleWifiChannel] Decoding JSON message");
          ackMsg = VeniceMessage.fromJson(jsonString);

        }
        else {
          final msgProto = VeniceMessageProto.fromBuffer(data);
          ackMsg = VeniceMessage.fromProtoBuf(msgProto);
        }
        on(DataChannelEvent.acknowledgment, ackMsg.messageId);
      });*/
    }
    else if(connectivityResults.isNotEmpty && Platform.isLinux ){

      debugPrint("[SimpleWifiChannel] linux system, getting wifi infos ");
        Map<String, String>? activeInterfaceInfo = await getIpAndMaskForActiveInterfaceByType("wifi");


        if(activeInterfaceInfo!=null){
          submask = activeInterfaceInfo['mask'];
          ip = activeInterfaceInfo['ip'];

          debugPrint("[SimpleWifiChannel] Wifi infos ip: $ip and mask $submask");
        }

    }

    if(ip == null || submask == null){
      throw WifiConnectionException(
          'You need to be connected to a Wifi Network');
    }



    List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4);

    for (var interface in interfaces) {
      for (var currentAddress in interface.addresses) {
        if (currentAddress.address == ip) {
          address = currentAddress;
          break;
        }
      }
    }

    if (address == null){
      throw WifiConnectionException(
          'You need to be connected to a Wifi Network');
    }

    server = await ServerSocket.bind(address, 0);
    server?.listen((clientSocket) {
      debugPrint(
          '[SimpleWifiChannel] Connection from ${clientSocket.remoteAddress
              .address}:${clientSocket.remotePort}');
      client = clientSocket;
    });

    // Send socket information to client.
    debugPrint("[SimpleWifiChannel] Sending Channel Metadata to client..");
    data = ChannelMetadata(super.identifier, address.address, submask, '', server!.port);
    await channel.sendChannelMetadata(
        data);
  }

  @override
  Future<void> sendMessage(VeniceMessage chunk) async {
    int length = -1;
    BytesBuilder packet = BytesBuilder();
    Uint8List data;

    if (useProtoBuf) {
      VeniceMessageProto chunkProto = chunk.toProtoBuf();
      data = chunkProto.writeToBuffer();
      length = data.length;
    }
    else{
      //client!.write(chunk.toBytes());
      String chunkJson = chunk.toJson();
      length= chunkJson.length;
      data = utf8.encode(chunkJson);
    }

    final messageLengthBytes = ByteData(4)..setUint32(0, length, Endian.big);

    /*packet.addByte((length >> 24) & 0xFF);
    packet.addByte((length >> 16) & 0xFF);
    packet.addByte((length >> 8) & 0xFF);
    packet.addByte(length & 0xFF);*/
    for (final currentByte in messageLengthBytes.buffer.asInt8List()){
      packet.addByte(currentByte);
    }


    packet.add(data);


    debugPrint("[SimpleWifiChannel] Sending data: "+data.toString());
    debugPrint("[SimpleWifiChannel] Data length: "+length.toString());
    //client!.add(messageLengthBytes.buffer.asInt8List());
    client!.add(packet.toBytes());
    await client!.flush();
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

  @override
  Future<void> dealWithClientConnections() async {

    while (client == null) {

      debugPrint("[SimpleWifiChannel] Waiting for client to connect...");
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint("[SimpleWifiChannel] Client Connected !");

    client!.listen((data) {
      VeniceMessage ackMsg;
      if (!useProtoBuf) {
        final jsonString = String.fromCharCodes(
            data); // Decode bytes to string
        debugPrint("[SimpleWifiChannel] JSON String Received: "+jsonString);
        debugPrint("[SimpleWifiChannel] Decoding JSON message");
        ackMsg = VeniceMessage.fromJson(jsonString);

      }
      else {
        final msgProto = VeniceMessageProto.fromBuffer(data);
        ackMsg = VeniceMessage.fromProtoBuf(msgProto);
      }
      on(DataChannelEvent.acknowledgment, ackMsg.messageId);
    });



  }

  int transformIpToInt(String ip){

    List<String>? ipParts = ip.split('.');
    int ipInt = -1;

    debugPrint("[SimpleWifiChannel] ip parts: $ipParts");

    if(ipParts.length==4) {
      ipInt = (int.parse(ipParts[0]) << 24) + (int.parse(ipParts[1]) <<
          16) + (int.parse(ipParts[2]) << 8) + int.parse(ipParts[3]); //part0*2^24 + part1*2^16 + part2*2^8 + part3*2^0
    }
    return ipInt;
  }

  int computeNetworkAsInt(String ip, String mask){
     int ipInt = transformIpToInt(ip);
     int maskInt = transformIpToInt(mask);

     debugPrint("[SimpleWifiChannel] ip int: $ipInt");
     debugPrint("[SimpleWifiChannel] mask int: $maskInt");

     debugPrint("[SimpleWifiChannel] ip int& mask int: ${ipInt & maskInt}");

     return ipInt & maskInt;
  }

  Future<String?> getActiveInterfaceByType(String interfaceType) async{

    String? activeInterface;

    ProcessResult nmcliCommandResult = await Process.run(
      'nmcli',
      ['-t', '-f', 'DEVICE,TYPE,STATE', 'device'],
    );

    if(nmcliCommandResult.exitCode==0) {
      String nmcliCommandResultStr = nmcliCommandResult.stdout.toString().trim();

      List<String> devicesInfo = nmcliCommandResultStr.split('\n');

      //<interfaceId>:<type>:<state>
      activeInterface =
          devicesInfo.firstWhere((deviceInfo) => deviceInfo.endsWith('$interfaceType:connected'), orElse: () => '');

      if(activeInterface.isEmpty){
        activeInterface = null;
      }
      else{
        activeInterface = activeInterface.split(':')[0];
      }



      /*for(String deviceInfo in devicesInfo){


        if(deviceInfo.contains('$interfaceType:connected')){
          activeInterface = deviceInfo.split(':')[0];
        }
      }*/

    }
    return activeInterface;
  }

  Future<Map<String,String>?> getIpAndMaskForActiveInterfaceByType(String interfaceType) async{
    Map<String,String>? networkInfo;

    String? activeInterface = await getActiveInterfaceByType(interfaceType);

    debugPrint("[SimpleWifiChannel] Active wifi interface $activeInterface");

    if(activeInterface!= null){

      ProcessResult nmcliCommandResult = await Process.run(
        'nmcli',
        ['-t', '-f', 'IP4.ADDRESS', 'device', 'show', activeInterface],
      );

      if (nmcliCommandResult.exitCode == 0) {

        //IP4.ADDRESS[<number>]:<address>
        String activeInterfaceInfo = nmcliCommandResult.stdout
            .toString()
            .trim()
            .split('\n')
            .firstWhere((info) => info.startsWith('IP4.ADDRESS'), orElse: () => '');

        debugPrint("[SimpleWifiChannel] Active wifi interface info $activeInterfaceInfo");

        if(activeInterfaceInfo.isNotEmpty){
          String ipWithCidr = activeInterfaceInfo.split(':')[1];

         if(ipWithCidr.contains('/')){
           //<ip>/<cidr>
           List<String> ipWithCidrSeparated = ipWithCidr.split('/');
           int cidrInt = int.parse(ipWithCidrSeparated[1]);

           networkInfo={"ip":ipWithCidrSeparated[0],
                       "mask":computeMaskFromCidr(cidrInt)
            };

         }
        }
      }
    }

    return networkInfo;

  }


  String computeMaskFromCidr(int cidr){
    int mask = 0xFFFFFFFF << (32 - cidr);
    return [
      (mask >> 24) & 255,
      (mask >> 16) & 255,
      (mask >> 8) & 255,
      mask & 255,
    ].join('.');

  }




}
