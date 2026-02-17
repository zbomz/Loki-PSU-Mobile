import 'dart:typed_data';

/// CRC16-MODBUS implementation matching the firmware's calculateCRC16Modbus().
///
/// Polynomial: 0xA001 (reversed 0x8005)
/// Initial value: 0xFFFF
/// Test vector: "123456789" -> 0x4B37
int crc16Modbus(Uint8List data) {
  int crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int j = 0; j < 8; j++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

/// Validate that the last 2 bytes of [packet] match the CRC of the preceding data.
bool validateCrc16(Uint8List packet) {
  if (packet.length < 3) return false;
  final calculated =
      crc16Modbus(Uint8List.sublistView(packet, 0, packet.length - 2));
  final received =
      packet[packet.length - 2] | (packet[packet.length - 1] << 8);
  return calculated == received;
}

/// Append CRC16 to [data] and return a new Uint8List with CRC appended.
Uint8List appendCrc16(Uint8List data) {
  final crc = crc16Modbus(data);
  final result = Uint8List(data.length + 2);
  result.setRange(0, data.length, data);
  result[data.length] = crc & 0xFF; // LSB
  result[data.length + 1] = (crc >> 8) & 0xFF; // MSB
  return result;
}
