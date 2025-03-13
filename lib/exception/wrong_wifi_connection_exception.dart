class WrongWifiConnectionException implements Exception {
  String cause;
  WrongWifiConnectionException(this.cause);
}