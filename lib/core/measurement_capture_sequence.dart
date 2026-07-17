class MeasurementCaptureTimestamps {
  final DateTime recordingStartedAt;
  final DateTime playbackStartedAt;
  final DateTime playbackCompletedAt;
  final DateTime recordingStoppedAt;

  const MeasurementCaptureTimestamps({
    required this.recordingStartedAt,
    required this.playbackStartedAt,
    required this.playbackCompletedAt,
    required this.recordingStoppedAt,
  });
}

/// Coordinates one capture without imposing an additional signal-duration
/// delay. Recorder and playback adapters remain outside this class so ordering
/// and failure behavior can be tested without platform plugins.
class MeasurementCaptureSequence {
  final DateTime Function() now;

  const MeasurementCaptureSequence({required this.now});

  Future<MeasurementCaptureTimestamps> run({
    required Future<void> Function() startRecorder,
    required bool Function() recorderIsReady,
    required Future<void> Function() playSignalToCompletion,
    required Future<void> Function() stopRecorder,
    required Future<void> Function() stopPlayback,
  }) async {
    await startRecorder();
    if (!recorderIsReady()) {
      throw StateError('The microphone could not start recording.');
    }
    final recordingStartedAt = now();
    final playbackStartedAt = now();
    await playSignalToCompletion();
    final playbackCompletedAt = now();
    await stopRecorder();
    final recordingStoppedAt = now();
    await stopPlayback();
    return MeasurementCaptureTimestamps(
      recordingStartedAt: recordingStartedAt,
      playbackStartedAt: playbackStartedAt,
      playbackCompletedAt: playbackCompletedAt,
      recordingStoppedAt: recordingStoppedAt,
    );
  }
}
