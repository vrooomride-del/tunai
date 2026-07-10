import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Consumer-facing input source preference.
/// This is UI/state only — no hardware write is performed.
/// Actual input switching is planned for a future v0.9_INPUT_SELECT phase.
enum ConsumerInputSource { auto, bluetooth, aux }

final selectedInputSourceProvider =
    StateProvider<ConsumerInputSource>((_) => ConsumerInputSource.auto);
