library wifi_data_channel;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/metadata/channel_metadata.dart';
import 'package:venice_core/channels/events/data_channel_event.dart';
import 'package:flutter/foundation.dart';
import 'package:venice_core/network/message.dart';
import 'package:venice_core/external/protobuf/dart_proto/protos/venice.pb.dart';
import 'package:wifi_data_channel/exception/wifi_connection_exception.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_data_channel/simple_wifi_utils.dart';

import 'package:wifi_data_channel/exception/wrong_wifi_connection_exception.dart';


/// This class allows the usage of actual wifi connection as data channel
class SimpleWifiDataChannel extends DataChannel {

  /// Constructor of the class
  ///
  /// [identifier] The Channel identifier
  SimpleWifiDataChannel(super.identifier);

  ///Port for listen for connections
  final int port = 62526;

  ///Socket enabling interactions with a client (mainly file transfers)
  Socket? client;

  ///Flag to indicate if protobuf serialisation is used
  bool useProtoBuf = true;

  ///Server socket for accepting connections from clients
  ServerSocket? server;



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

      debugPrint("[SimpleWifiDataChannel:initReceiver]: Connecting to wifi: $networkName");

      bool connected = await connectToRegisteredNetwork(networkName as String);

      if (!connected) {
        throw WifiConnectionException(
            'Unable to connect to ${data.apIdentifier} network');
      }
    }
    else
    {
      int remoteNetworkInt = SimpleWifiUtils.computeNetworkAsInt(data.address, data.apIdentifier);
      int localNetworkInt = SimpleWifiUtils.computeNetworkAsInt(ipChecked, maskChecked); //This value has to be correct because we are on the same network

      debugPrint('[SimpleWifiChannel::initReceiver] Expected BSSID: ${data.apIdentifier}');
      debugPrint('[SimpleWifiChannel::initReceiver] Name: $networkName');


      debugPrint('[SimpleWifiChannel::initReceiver] BSSID: $bssid');
      debugPrint('[SimpleWifiChannel::initReceiver] IP: $ip');

      debugPrint('[SimpleWifiChannel::initReceiver] remoteNetworkInt: $remoteNetworkInt');
      debugPrint('[SimpleWifiChannel::initReceiver] localNetworkInt: $localNetworkInt');

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
        debugPrint('[SimpleWifiChannel::initReceiver] Connecting to: ${data.address}:${data.port}');
        final socket = await Socket.connect(data.address, data.port,
            timeout: const Duration(seconds: 5));
        debugPrint(
            '[SimpleWifiChannel::initReceiver] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        client = socket;
        connected = true;

      } catch (err) {
        debugPrint("[SimpleWifiChannel::initReceiver] Failed to connect to host, retrying...");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Reception listener
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
          debugPrint("SimpleWifiChannel::client.listen]==> MESSAGE RECEIVED $jsonString");
          msg = VeniceMessage.fromJson(jsonString);
        }
        else {
          final msgProto = VeniceMessageProto.fromBuffer(messageBytes);
          msg = VeniceMessage.fromProtoBuf(msgProto);
        }

        try {
          int msgId = msg.messageId;
          debugPrint("SimpleWifiChannel::client.listen]==> MESSAGE #$msgId COMPLETE");
          on(DataChannelEvent.data, msg);
          debugPrint("SimpleWifiChannel::client.listen]==> Sending acknowledgement");
          if (!useProtoBuf){
            debugPrint("SimpleWifiChannel::client.listen]==> Sending JSON Ack");
            client!.write(VeniceMessage.acknowledgement(msgId).toJson());
          }
          else {
            debugPrint("SimpleWifiChannel::client.listen]==> Sending ProtoBuf Ack");
            VeniceMessageProto messageProto = VeniceMessage.acknowledgement(msgId).toProtoBuf();
            Uint8List data = messageProto.writeToBuffer();
            client!.add(data);
            await client!.flush();
          }
          await client!.flush();
          debugPrint("SimpleWifiChannel::client.listen]==> Acknowledgement sent");
          buffer.removeRange(0, 4 + messageLength);
          messageLength = -1;
        } catch (e) {
          debugPrint("SimpleWifiChannel::client.listen]==> MESSAGE NOT COMPLETE, WAITING FOR NEXT DATA");
        }

      }




    });
  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {

    final List<ConnectivityResult> connectivityResults = await (Connectivity().checkConnectivity());

    debugPrint("[SimpleWifiChannel::initSender] initSender - Results List: ${connectivityResults.toString()}");
    final networkInfoManager = NetworkInfo();
    String? ssid;
    String? submask;
    String? ip;
    InternetAddress? address;

    if (connectivityResults.contains(ConnectivityResult.wifi)) {

      ssid = await networkInfoManager.getWifiName();
      submask = (await networkInfoManager.getWifiSubmask())!;
      String? bssid = (await networkInfoManager.getWifiBSSID())!;
      String? gatewayIp = (await networkInfoManager.getWifiGatewayIP())!;

      ip = (await networkInfoManager.getWifiIP())!;

      debugPrint("[SimpleWifiChannel::initSender] Sender successfully initialized.");
      debugPrint("[SimpleWifiChannel::initSender]     IP: $ip");
      debugPrint("[SimpleWifiChannel::initSender]     SSID: $ssid");
      debugPrint("[SimpleWifiChannel::initSender]     BSSID: $bssid");
      debugPrint("[SimpleWifiChannel::initSender]     Gateway: $gatewayIp");
      debugPrint("[SimpleWifiChannel::initSender]     Submask: $submask");

    }
    else if(connectivityResults.isNotEmpty && Platform.isLinux ){

      debugPrint("[SimpleWifiChannel::initSender] linux system, getting wifi information ");
        Map<String, String>? activeInterfaceInfo = await SimpleWifiUtils.getIpAndMaskForActiveInterfaceByType("wifi");

        if(activeInterfaceInfo!=null){
          submask = activeInterfaceInfo['mask'];
          ip = activeInterfaceInfo['ip'];

          debugPrint("[SimpleWifiChannel::initSender] Wifi information ip: $ip and mask $submask");
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
          '[SimpleWifiChannel::initSender] Connection from ${clientSocket.remoteAddress
              .address}:${clientSocket.remotePort}');
      client = clientSocket;

    });

    // Send socket information to client.
    debugPrint("[SimpleWifiChannel::initSender] Sending Channel Metadata to client..");
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
      String chunkJson = chunk.toJson();
      length= chunkJson.length;
      data = utf8.encode(chunkJson);
    }

    final messageLengthBytes = ByteData(4)..setUint32(0, length, Endian.big);

    for (final currentByte in messageLengthBytes.buffer.asInt8List()){
      packet.addByte(currentByte);
    }


    packet.add(data);


    debugPrint("[SimpleWifiChannel::sendMessage] Sending data: ${data.toString()}");
    debugPrint("[SimpleWifiChannel::sendMessage] Data length: ${length.toString()}");

    client!.add(packet.toBytes());
    await client!.flush();
  }

  @override
  Future<void> close() async {
    if (client != null) {
      client!.close();
    }
  }

  /// Connects to a registred network git the given ssid
  ///
  /// [ssid] SSID of the known network
  Future<bool> connectToRegisteredNetwork(String ssid) async {
    return SimpleWifiUtils.connectToRegisteredWifi(ssid);
  }

  @override
  Future<void> dealWithClientConnections() async {

    while (client == null) {

      debugPrint("[SimpleWifiChannel::dealWithClientConnections] Waiting for client to connect...");
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint("[SimpleWifiChannel::dealWithClientConnections] Client Connected !");

    client!.listen((data) {
      VeniceMessage ackMsg;
      if (!useProtoBuf) {
        final jsonString = String.fromCharCodes(
            data); // Decode bytes to string
        debugPrint("[SimpleWifiChannel::dealWithClientConnections] JSON String Received: $jsonString");
        debugPrint("[SimpleWifiChannel::dealWithClientConnections] Decoding JSON message");
        ackMsg = VeniceMessage.fromJson(jsonString);

      }
      else {
        final msgProto = VeniceMessageProto.fromBuffer(data);
        ackMsg = VeniceMessage.fromProtoBuf(msgProto);
      }
      on(DataChannelEvent.acknowledgment, ackMsg.messageId);
    });
  }
}