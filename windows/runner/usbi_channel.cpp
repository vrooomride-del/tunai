// USBi MethodChannel stub — tunai/usbi
//
// All methods return NOT_IMPLEMENTED structured errors until the Windows
// WinUSB / libusb-win32 backend is wired in.
//
// IMPORTANT: Do NOT fake success. The Dart backend distinguishes
// MissingPluginException (channel not registered) from PlatformException
// (channel registered, method returned error). This stub registers the
// channel so Dart receives PlatformException{code="NOT_IMPLEMENTED"}
// instead of MissingPluginException, allowing the UI to show
// "implementation pending" rather than "channel missing".
//
// When implementing real WinUSB calls:
//   1. Include <winusb.h> and <setupapi.h>
//   2. Enumerate devices with SetupDiGetClassDevs using VID 0x0456
//   3. Open with WinUsb_Initialize
//   4. usbi_send_setup  -> WinUsb_ControlTransfer (setup packet)
//   5. usbi_send_body   -> WinUsb_WritePipe (bulk out)
//   6. usbi_read_ack    -> WinUsb_ReadPipe (bulk in, 8 bytes)
//   7. usbi_close       -> WinUsb_Free + CloseHandle
//
// Do NOT auto-write. All execution is initiated by the Dart executor
// after the 7-guard chain passes.

#include "usbi_channel.h"

#include <flutter/encodable_value.h>

namespace tunai {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

// Helper: send a structured NOT_IMPLEMENTED error.
void NotImplemented(
    std::unique_ptr<MethodResult<EncodableValue>>& result,
    const std::string& method_name) {
  result->Error(
      "NOT_IMPLEMENTED",
      method_name + ": Windows USBi backend not yet implemented. "
          "Register WinUSB / libusb-win32 calls here.",
      EncodableValue(flutter::EncodableMap{
          {EncodableValue("method"), EncodableValue(method_name)},
          {EncodableValue("status"), EncodableValue(std::string("pending"))},
      }));
}

void HandleUsbiMethod(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  if (method == "usbi_is_available") {
    // TODO(t4b-windows): Enumerate USB devices with VID 0x0456 via SetupAPI.
    NotImplemented(result, "usbi_is_available");

  } else if (method == "usbi_list_devices") {
    // TODO(t4b-windows): Return list of {vid, pid, serial, description} maps.
    NotImplemented(result, "usbi_list_devices");

  } else if (method == "usbi_open_device") {
    // TODO(t4b-windows): Open device with WinUsb_Initialize.
    // Return {success: true} on success, {access_denied: true} on ERROR_ACCESS_DENIED,
    // {success: false, detail: <message>} on other failures.
    NotImplemented(result, "usbi_open_device");

  } else if (method == "usbi_send_setup") {
    // TODO(t4b-windows): WinUsb_ControlTransfer with the 8-byte setup packet.
    // args["bytes"] is a Uint8List: 40 B2 00 00 01 01 06 00
    NotImplemented(result, "usbi_send_setup");

  } else if (method == "usbi_send_body") {
    // TODO(t4b-windows): WinUsb_WritePipe with the 6-byte body packet.
    // args["bytes"] is a Uint8List: [addr 2B BE] + [data 4B BE, 8.24 fixed-point]
    NotImplemented(result, "usbi_send_body");

  } else if (method == "usbi_read_ack") {
    // TODO(t4b-windows): WinUsb_ReadPipe, return 8 bytes.
    // ACK success: byte[6] == 0x01
    NotImplemented(result, "usbi_read_ack");

  } else if (method == "usbi_close") {
    // TODO(t4b-windows): WinUsb_Free + CloseHandle.
    NotImplemented(result, "usbi_close");

  } else if (method == "usbi_write_adau1701_param") {
    // ADAU1701 I2C parameter write — DIFFERENT from the ADAU1466 SPI methods above.
    //
    // This method writes one 4-byte parameter to the ADAU1701 via USBi → I2C.
    // The ADAU1466 send_setup / send_body / read_ack packet format must NOT be
    // reused here; the ADAU1701 uses I2C, not SPI.
    //
    // args: Flutter EncodableMap with:
    //   "i2c_address"   (int) = 0x68 — DSP I2C address (7-bit device addr)
    //   "param_address" (int) = 0x0000–0xFFFF — ADAU1701 parameter address
    //   "data"          (List<int>) = 4 bytes, Big Endian, 5.23 fixed-point
    //
    // EEPROM I2C address 0xA0 must be refused:
    //   if i2c_address == 0xA0: return Error("EEPROM_WRITE_BLOCKED", ...)
    //
    // TODO(adau1701-windows): Implement WinUSB → I2C write:
    //   1. Retrieve device handle (open if not already open).
    //   2. Validate: refuse i2c_address == 0xA0.
    //   3. Build I2C write packet for USBi:
    //      - I2C write address byte: (i2c_address << 1) | 0  = 0xD0 for 0x68
    //      - Packet: [i2c_write_byte][param_addr_hi][param_addr_lo][d0][d1][d2][d3]
    //      - Total 7 bytes of I2C payload
    //   4. Issue USBi control transfer to start write:
    //      - bmRequestType=0x40, bRequest=0x09 or per USBi host API
    //      - Specify: I2C mode, 7 data bytes
    //   5. Write the 7-byte I2C payload via WinUsb_WritePipe on bulk-out endpoint
    //   6. Return void on success, PlatformException on failure.
    //
    // Note: USBi bulk endpoint numbers differ from the SPI (ADAU1466) setup.
    //       Identify correct endpoint by device descriptor or empirically.
    NotImplemented(result, "usbi_write_adau1701_param");

  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterUsbiChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_shared<flutter::MethodChannel<EncodableValue>>(
      messenger,
      "tunai/usbi",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleUsbiMethod(call, std::move(result));
      });

  // Keep the channel alive for the lifetime of the app.
  // (The shared_ptr is captured by the lambda via the channel variable;
  //  in production code, store it as a member of FlutterWindow.)
}

}  // namespace tunai
