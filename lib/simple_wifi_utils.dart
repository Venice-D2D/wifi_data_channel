import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:wifi_data_channel/exception/wrong_wifi_connection_exception.dart';

/// Class that provides tools requires to deal with wifi connections in Linux and Android
class SimpleWifiUtils{
  static const platform = MethodChannel('wifi/connect');

  ///Connects to the provide wifi. Returns true if success
  ///
  ///[ssid] The ssid related to the wifi network
  static Future<bool> connectToRegisteredWifi(String ssid) async{

    bool connected = false;

    if(Platform.isAndroid){
      try {
        final String result = await platform.invokeMethod(
            'connectToRegisteredNetwork', {'ssid': ssid});
        debugPrint("[SimpleWifiUtils::connectToRegisteredWifi] Android wifi connection result: $result");
        if (result.contains("[SimpleWifiUtils::connectToRegisteredWifi] Connected to")) {
          connected = true;
        }
      } on PlatformException catch (e) {
        debugPrint("Failed to connect: ${e.message}");
      }

    }
    else if(Platform.isLinux){

      final result = await Process.run(
        'nmcli',
        ['connection', 'up', ssid],
      );

      connected= result.exitCode == 0;

    }
    else{
      throw WrongWifiConnectionException("Unsupported Platform");
    }
    return Future.value(connected);

  }

  /// Computes the mask for a given CIDR (Classless Inter-Domain Routing)
  ///
  /// [cidr] Classless Inter-Domain Routing
  static String computeMaskFromCidr(int cidr){
    int mask = 0xFFFFFFFF << (32 - cidr);
    return [
      (mask >> 24) & 255,
      (mask >> 16) & 255,
      (mask >> 8) & 255,
      mask & 255,
    ].join('.');

  }

  /// Returns the active interface for the given type on a Linux platform via nmcli
  ///
  /// [interfaceType] The interface type
  static Future<String?> getActiveInterfaceByType(String interfaceType) async{

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


  /// Get the IP and Mask for the given interface type for Linux Platform via nmcli.
  /// Information is stored in a map
  ///
  /// [interfaceType] The interface to get the infrmation
  static Future<Map<String,String>?> getIpAndMaskForActiveInterfaceByType(String interfaceType) async{
    Map<String,String>? networkInfo;

    String? activeInterface = await getActiveInterfaceByType(interfaceType);

    debugPrint("[SimpleWifiChannel::getIpAndMaskForActiveInterfaceByType] Active wifi interface $activeInterface");

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

        debugPrint("[SimpleWifiChannel::getIpAndMaskForActiveInterfaceByType] Active wifi interface info $activeInterfaceInfo");

        if(activeInterfaceInfo.isNotEmpty){
          String ipWithCidr = activeInterfaceInfo.split(':')[1];

          if(ipWithCidr.contains('/')){
            //<ip>/<cidr>
            List<String> ipWithCidrSeparated = ipWithCidr.split('/');
            int cidrInt = int.parse(ipWithCidrSeparated[1]);

            networkInfo={"ip":ipWithCidrSeparated[0],
              "mask":SimpleWifiUtils.computeMaskFromCidr(cidrInt)
            };

          }
        }
      }
    }

    return networkInfo;

  }

  /// Transforms a given IP  into an integer by using
  /// the formula part0*2^24 + part1*2^16 + part2*2^8 + part3*2^0
  ///
  /// [ip] The IP string with format <part0.part1.part2.part3>
  static  int transformIpToInt(String ip){

    List<String>? ipParts = ip.split('.');
    int ipInt = -1;

    debugPrint("[SimpleWifiUtils::transformIpToInt] ip parts: $ipParts");

    if(ipParts.length==4) {
      ipInt = (int.parse(ipParts[0]) << 24) + (int.parse(ipParts[1]) <<
          16) + (int.parse(ipParts[2]) << 8) + int.parse(ipParts[3]); //part0*2^24 + part1*2^16 + part2*2^8 + part3*2^0
    }
    return ipInt;
  }


  /// Represents a network as an int by using an IP and Mask
  ///
  /// [ip] A network IP
  /// [mask] Mask related to the network
  static int computeNetworkAsInt(String ip, String mask){
    int ipInt = transformIpToInt(ip);
    int maskInt = transformIpToInt(mask);

    debugPrint("[SimpleWifiUtils::transformIpToInt] ip int: $ipInt");
    debugPrint("[SimpleWifiUtils::transformIpToInt] mask int: $maskInt");

    debugPrint("[SimpleWifiUtils::transformIpToInt] ip int& mask int: ${ipInt & maskInt}");

    return ipInt & maskInt;
  }

}