// ADAU1701 v0.8 Export14 주소 상수
// ─── Master Volume (27-byte BLE 프레임, 5.23 고정소수점) ─────────────────────
const kAdau1701MasterVolR = 0x0004;
const kAdau1701MasterVolL = 0x0005;

// ─── 절대 금지 ────────────────────────────────────────────────────────────────
// ignore: constant_identifier_names
const kAdau1701EepromI2cAddr = 0xA0; // NEVER WRITE — I2C EEPROM 주소
