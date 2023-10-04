import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_data_channel/wifi_data_channel.dart';

class TestNetworkInterface extends NetworkInterface {
  @override
  final String name;
  @override
  final int index = -1;
  @override
  late final List<InternetAddress> addresses;

  TestNetworkInterface(this.name, List<String> addressesList) {
    addresses = addressesList.map((e) => InternetAddress(e)).toList();
  }
}

void main() {
  late WifiDataChannel canal;
  setUp(() {
    canal = WifiDataChannel("wifi");
  });

  group('retrieveHotspotIPAddress', () {
    test('should find new address', () {
      String hotspotAddress = '192.168.53.71';
      NetworkInterface ni1 = TestNetworkInterface("wlan0", ['10.201.0.146']);
      NetworkInterface ni2 = TestNetworkInterface("v4-rmnet_data2", ['192.0.0.4']);
      NetworkInterface hotspot = TestNetworkInterface("wlan", [hotspotAddress]);

      InternetAddress result = canal.retrieveHotspotIPAddress([ni1, hotspot, ni2], [ni1, ni2]);
      expect(result.address, hotspotAddress);
    });

    test('should not find address without second parameter', () {
      String hotspotAddress = '192.168.53.71';
      NetworkInterface ni1 = TestNetworkInterface("wlan0", ['10.201.0.146']);
      NetworkInterface ni2 = TestNetworkInterface("v4-rmnet_data2", ['192.0.0.4']);
      NetworkInterface hotspot = TestNetworkInterface("wlan", [hotspotAddress]);

      expect(() => canal.retrieveHotspotIPAddress([ni1, hotspot, ni2], null),
          throwsA(predicate((e) => e is StateError
              && e.message == 'Could not retrieve hotspot IP address from provided information.')));
    });

    test('should return single private address', () {
      String hotspotAddress = '10.201.0.146';
      NetworkInterface ni1 = TestNetworkInterface("wlan0", [hotspotAddress]);
      NetworkInterface ni2 = TestNetworkInterface("v4-rmnet_data2", ['192.0.0.4']);

      InternetAddress result = canal.retrieveHotspotIPAddress([ni1, ni2], null);
      expect(result.address, hotspotAddress);
    });
  });
}