import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:wifi_data_channel/wifi_data_channel.dart';

extension AccessPointUtils on DataChannel {
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
}