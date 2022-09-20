library wifi_data_channel;

import 'package:channel_multiplexed_scheduler/channels/abstractions/bootstrap_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/abstractions/data_channel.dart';
import 'package:channel_multiplexed_scheduler/channels/channel_metadata.dart';
import 'package:channel_multiplexed_scheduler/file/file_chunk.dart';


class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);

  @override
  Future<void> initReceiver(ChannelMetadata data) {
    // TODO: implement initReceiver
    throw UnimplementedError();
  }

  @override
  Future<void> initSender(BootstrapChannel channel) {
    // TODO: implement initSender
    throw UnimplementedError();
  }

  @override
  Future<void> sendChunk(FileChunk chunk) {
    // TODO: implement sendChunk
    throw UnimplementedError();
  }
}