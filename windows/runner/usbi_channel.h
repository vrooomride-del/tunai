#ifndef RUNNER_USBI_CHANNEL_H_
#define RUNNER_USBI_CHANNEL_H_

// USBi MethodChannel stub for TUNAI PRO engineering backend.
//
// Channel name: tunai/usbi
//
// Methods handled:
//   usbi_is_available  -> map {available: bool, device_count: int, detail: string?}
//   usbi_list_devices  -> list<map>
//   usbi_open_device   -> map {success: bool, access_denied: bool, detail: string?}
//   usbi_send_setup    -> void  (args: {bytes: Uint8List})
//   usbi_send_body     -> void  (args: {bytes: Uint8List})
//   usbi_read_ack      -> Uint8List (8 bytes)
//   usbi_close         -> void
//
// This stub returns structured NOT_IMPLEMENTED errors for all methods.
// Replace method bodies with actual WinUSB / libusb-win32 calls when
// the Windows engineering backend is ready.
//
// ADI USBi expected VID: 0x0456. PID is not hardcoded.
// Do NOT auto-write on registration. All writes go through the Dart
// ProUsbiTemporaryExecutor which enforces the 7-guard chain.

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

namespace tunai {

// Registers the tunai/usbi MethodChannel on the given messenger.
// Call from FlutterWindow::OnCreate after RegisterPlugins().
void RegisterUsbiChannel(flutter::BinaryMessenger* messenger);

}  // namespace tunai

#endif  // RUNNER_USBI_CHANNEL_H_
