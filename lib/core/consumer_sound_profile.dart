import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_scan_result.dart';
import 'tune_plan.dart';

enum ConsumerProfileStatus { draft, ready, active }

enum ConsumerProfileGenerationStatus { legacy, generated }

enum ConsumerDspDeploymentRecordResult { applied, restored, failed, blocked }

class ConsumerDspDeploymentRecord {
  final String tunePlanId;
  final String deviceIdentifier;
  final DateTime attemptedAt;
  final int bandCount;
  final ConsumerDspDeploymentRecordResult result;
  final bool dspApplied;
  final String? failureCategory;

  const ConsumerDspDeploymentRecord({
    required this.tunePlanId,
    required this.deviceIdentifier,
    required this.attemptedAt,
    required this.bandCount,
    required this.result,
    required this.dspApplied,
    this.failureCategory,
  });

  Map<String, dynamic> toJson() => {
        'tunePlanId': tunePlanId,
        'deviceIdentifier': deviceIdentifier,
        'attemptedAt': attemptedAt.toIso8601String(),
        'bandCount': bandCount,
        'result': result.name,
        'dspApplied': dspApplied,
        if (failureCategory != null) 'failureCategory': failureCategory,
      };

  factory ConsumerDspDeploymentRecord.fromJson(Map<String, dynamic> json) =>
      ConsumerDspDeploymentRecord(
        tunePlanId: json['tunePlanId'] as String,
        deviceIdentifier: json['deviceIdentifier'] as String,
        attemptedAt: DateTime.parse(json['attemptedAt'] as String),
        bandCount: json['bandCount'] as int,
        result: ConsumerDspDeploymentRecordResult.values
            .byName(json['result'] as String),
        dspApplied: json['dspApplied'] as bool,
        failureCategory: json['failureCategory'] as String?,
      );
}

/// Taxonomy tag for consumer sound profiles.
/// Note: `factorySound` represents the device baseline (cannot use `factory` — Dart keyword).
enum ConsumerProfileType {
  tunaiTune,
  myTune,
  roomProfile,
  reference,
  factorySound;

  String toJson() => name;

  static ConsumerProfileType fromJson(String? s) => s == null
      ? ConsumerProfileType.tunaiTune
      : ConsumerProfileType.values.firstWhere(
          (e) => e.name == s,
          orElse: () => ConsumerProfileType.tunaiTune,
        );
}

extension ConsumerProfileTypeLabels on ConsumerProfileType {
  String label(bool ko) => ko ? _ko : _en;

  String get _ko => switch (this) {
        ConsumerProfileType.tunaiTune => 'TUNAI Tune',
        ConsumerProfileType.myTune => 'My Tune',
        ConsumerProfileType.roomProfile => '공간 프로파일',
        ConsumerProfileType.reference => '레퍼런스',
        ConsumerProfileType.factorySound => 'Factory Sound',
      };

  String get _en => switch (this) {
        ConsumerProfileType.tunaiTune => 'TUNAI Tune',
        ConsumerProfileType.myTune => 'My Tune',
        ConsumerProfileType.roomProfile => 'Room Profile',
        ConsumerProfileType.reference => 'Reference',
        ConsumerProfileType.factorySound => 'Factory Sound',
      };
}

class ConsumerSoundProfile {
  final String id;
  final String name;
  final String roomType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String micProfileName;
  final String confidence;
  final bool isActive;
  final ConsumerProfileStatus status;
  final List<RoomScanResultCard> resultCards;
  // Consumer-friendly Sound Score — simulated estimate, not a technical measurement.
  final int? soundScoreBefore;
  final int? soundScoreAfter;
  final ConsumerProfileType profileType;
  final String? measurementId;
  final String? tunePlanId;
  final bool isSelected;
  final ConsumerProfileGenerationStatus generationStatus;
  final TuneDeploymentStatus deploymentStatus;
  final ConsumerDspDeploymentRecord? dspDeploymentRecord;

  const ConsumerSoundProfile({
    required this.id,
    required this.name,
    required this.roomType,
    required this.createdAt,
    required this.updatedAt,
    required this.micProfileName,
    required this.confidence,
    required this.isActive,
    required this.status,
    required this.resultCards,
    this.soundScoreBefore,
    this.soundScoreAfter,
    this.profileType = ConsumerProfileType.tunaiTune,
    this.measurementId,
    this.tunePlanId,
    this.isSelected = false,
    this.generationStatus = ConsumerProfileGenerationStatus.legacy,
    this.deploymentStatus = TuneDeploymentStatus.unknown,
    this.dspDeploymentRecord,
  });

  int? get soundScoreImprovement {
    if (soundScoreBefore == null || soundScoreAfter == null) return null;
    return soundScoreAfter! - soundScoreBefore!;
  }

  ConsumerSoundProfile copyWith({
    String? name,
    bool? isActive,
    ConsumerProfileStatus? status,
    DateTime? updatedAt,
    int? soundScoreBefore,
    int? soundScoreAfter,
    ConsumerProfileType? profileType,
    bool? isSelected,
    ConsumerProfileGenerationStatus? generationStatus,
    TuneDeploymentStatus? deploymentStatus,
    ConsumerDspDeploymentRecord? dspDeploymentRecord,
  }) =>
      ConsumerSoundProfile(
        id: id,
        name: name ?? this.name,
        roomType: roomType,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        micProfileName: micProfileName,
        confidence: confidence,
        isActive: isActive ?? this.isActive,
        status: status ?? this.status,
        resultCards: resultCards,
        soundScoreBefore: soundScoreBefore ?? this.soundScoreBefore,
        soundScoreAfter: soundScoreAfter ?? this.soundScoreAfter,
        profileType: profileType ?? this.profileType,
        measurementId: measurementId,
        tunePlanId: tunePlanId,
        isSelected: isSelected ?? this.isSelected,
        generationStatus: generationStatus ?? this.generationStatus,
        deploymentStatus: deploymentStatus ?? this.deploymentStatus,
        dspDeploymentRecord: dspDeploymentRecord ?? this.dspDeploymentRecord,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roomType': roomType,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'micProfileName': micProfileName,
        'confidence': confidence,
        'isActive': isActive,
        'status': status.name,
        'resultCards': resultCards.map((c) => c.toJson()).toList(),
        if (soundScoreBefore != null) 'soundScoreBefore': soundScoreBefore,
        if (soundScoreAfter != null) 'soundScoreAfter': soundScoreAfter,
        'profileType': profileType.toJson(),
        if (measurementId != null) 'measurementId': measurementId,
        if (tunePlanId != null) 'tunePlanId': tunePlanId,
        'isSelected': isSelected,
        'generationStatus': generationStatus.name,
        'deploymentStatus': deploymentStatus.name,
        if (dspDeploymentRecord != null)
          'dspDeploymentRecord': dspDeploymentRecord!.toJson(),
      };

  factory ConsumerSoundProfile.fromJson(Map<String, dynamic> j) =>
      ConsumerSoundProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        roomType: j['roomType'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        micProfileName: j['micProfileName'] as String,
        confidence: j['confidence'] as String,
        isActive: j['isActive'] as bool,
        status: ConsumerProfileStatus.values.byName(j['status'] as String),
        resultCards: (j['resultCards'] as List)
            .map((c) => RoomScanResultCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        soundScoreBefore: j['soundScoreBefore'] as int?,
        soundScoreAfter: j['soundScoreAfter'] as int?,
        profileType: ConsumerProfileType.fromJson(j['profileType'] as String?),
        measurementId: j['measurementId'] as String?,
        tunePlanId: j['tunePlanId'] as String?,
        isSelected: j['isSelected'] as bool? ?? false,
        generationStatus: ConsumerProfileGenerationStatus.values.byName(
          j['generationStatus'] as String? ?? 'legacy',
        ),
        // A persisted `applied` status is historical — it records that DSP was
        // applied in a prior session. On load the device may have been reset or
        // power-cycled, so the current confidence is unknown until the user
        // explicitly reapplies in the current session. The dspDeploymentRecord
        // below preserves the historical success metadata unchanged.
        deploymentStatus: () {
          final persisted = TuneDeploymentStatus.values.byName(
            j['deploymentStatus'] as String? ?? 'unknown',
          );
          return persisted == TuneDeploymentStatus.applied
              ? TuneDeploymentStatus.unknown
              : persisted;
        }(),
        dspDeploymentRecord: j['dspDeploymentRecord'] == null
            ? null
            : ConsumerDspDeploymentRecord.fromJson(
                Map<String, dynamic>.from(j['dspDeploymentRecord'] as Map),
              ),
      );
}

// ── UI label helpers (stored values are English) ─────────────────────────────

String roomTypeLabelKo(String roomType) => switch (roomType) {
      'Living Room' => '거실',
      'Desk' => '책상 위',
      'Near Wall' => '벽 가까이',
      'Studio' => '작업실',
      'Custom' => '직접 설정',
      _ => roomType,
    };

String micProfileLabelKo(String micProfileName) => switch (micProfileName) {
      'Generic Phone Mic' => '기본 휴대폰 마이크',
      _ => micProfileName,
    };

extension ConsumerSoundProfileLabels on ConsumerSoundProfile {
  String get roomTypeLabel => roomTypeLabelKo(roomType);
  String get roomTypeLabelEn => roomType;
  String micLabel(bool ko) =>
      ko ? micProfileLabelKo(micProfileName) : micProfileName;
}

const _kKey = 'tunai_consumer_sound_profiles';

class ConsumerSoundProfileNotifier
    extends StateNotifier<List<ConsumerSoundProfile>> {
  ConsumerSoundProfileNotifier() : super([]) {
    _hydrated = _load();
  }

  late final Future<void> _hydrated;

  ConsumerSoundProfile? get selectedProfile =>
      state.where((profile) => profile.isSelected).firstOrNull;

  Future<void> reload() async {
    await _hydrated;
    await _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        state = list
            .map(
                (e) => ConsumerSoundProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
        _kKey, jsonEncode(state.map((p) => p.toJson()).toList()));
    if (!saved) throw StateError('The Sound Profile could not be saved.');
  }

  Future<void> add(ConsumerSoundProfile profile) async {
    await _hydrated;
    state = [profile, ...state];
    await _persist();
  }

  Future<void> upsertAndActivate(ConsumerSoundProfile profile) async {
    await _hydrated;
    final now = DateTime.now();
    final active = profile.copyWith(
      isActive: true,
      status: ConsumerProfileStatus.active,
      updatedAt: now,
    );
    final matchingIndex = state.indexWhere(
      (candidate) =>
          candidate.id == profile.id ||
          (candidate.roomType == profile.roomType &&
              candidate.micProfileName == profile.micProfileName &&
              _sameResultCards(candidate.resultCards, profile.resultCards)),
    );
    final next = state
        .map((candidate) => candidate.copyWith(
              isActive: false,
              status: ConsumerProfileStatus.ready,
            ))
        .toList();
    if (matchingIndex == -1) {
      state = [active, ...next];
    } else {
      next[matchingIndex] = active;
      state = next;
    }
    await _persist();
  }

  Future<void> upsertGeneratedAndSelect(ConsumerSoundProfile profile) async {
    await _hydrated;
    if (profile.measurementId == null || profile.tunePlanId == null) {
      throw StateError(
          'Generated profiles require measurement and TunePlan links.');
    }
    final previous = state;
    final selected = profile.copyWith(
      isActive: false,
      isSelected: true,
      status: ConsumerProfileStatus.ready,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
      updatedAt: DateTime.now(),
    );
    final remaining = state
        .where((candidate) =>
            candidate.id != profile.id &&
            candidate.tunePlanId != profile.tunePlanId)
        .map((candidate) => candidate.copyWith(isSelected: false))
        .toList();
    state = [selected, ...remaining];
    try {
      await _persist();
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  Future<void> setActive(String id) async {
    await _hydrated;
    final now = DateTime.now();
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(
            isActive: true,
            status: ConsumerProfileStatus.active,
            updatedAt: now);
      }
      return p.copyWith(isActive: false, status: ConsumerProfileStatus.ready);
    }).toList();
    await _persist();
  }

  Future<void> recordDspDeployment(
    String profileId,
    ConsumerDspDeploymentRecord record,
  ) async {
    await _hydrated;
    final index = state.indexWhere((profile) => profile.id == profileId);
    if (index == -1) throw StateError('Sound Profile not found.');
    final previous = state;
    final next = [...state];
    next[index] = next[index].copyWith(
      deploymentStatus: _deploymentStatusFor(record),
      dspDeploymentRecord: record,
      updatedAt: record.attemptedAt,
    );
    state = next;
    try {
      await _persist();
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  /// Maps a deployment record to the correct current-confidence status.
  ///
  /// Rules:
  ///   applied  → applied        (full success in this session)
  ///   restored → notDeployed    (rollback succeeded, DSP is back to baseline)
  ///   blocked  → notDeployed    (nothing was written)
  ///   failed   → unknown        (partial write + failed rollback; device state
  ///                              is uncertain — never claim notDeployed)
  static TuneDeploymentStatus _deploymentStatusFor(
    ConsumerDspDeploymentRecord record,
  ) =>
      switch (record.result) {
        ConsumerDspDeploymentRecordResult.applied =>
          TuneDeploymentStatus.applied,
        ConsumerDspDeploymentRecordResult.restored =>
          TuneDeploymentStatus.notDeployed,
        ConsumerDspDeploymentRecordResult.blocked =>
          TuneDeploymentStatus.notDeployed,
        ConsumerDspDeploymentRecordResult.failed =>
          TuneDeploymentStatus.unknown,
      };

  Future<void> deactivateAll() async {
    await _hydrated;
    state = state
        .map((p) =>
            p.copyWith(isActive: false, status: ConsumerProfileStatus.ready))
        .toList();
    await _persist();
  }

  /// Connection transitions cannot prove that volatile device DSP state was
  /// retained. Historical deployment records remain available.
  Future<void> markCurrentDspConfidenceUnknown() async {
    await _hydrated;
    final previous = state;
    state = state
        .map((profile) => profile.copyWith(
              deploymentStatus: TuneDeploymentStatus.unknown,
            ))
        .toList(growable: false);
    if (_sameProfiles(previous, state)) return;
    try {
      await _persist();
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _hydrated;
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }
}

bool _sameResultCards(
        List<RoomScanResultCard> left, List<RoomScanResultCard> right) =>
    jsonEncode(left.map((card) => card.toJson()).toList()) ==
    jsonEncode(right.map((card) => card.toJson()).toList());

bool _sameProfiles(
        List<ConsumerSoundProfile> left, List<ConsumerSoundProfile> right) =>
    jsonEncode(left.map((profile) => profile.toJson()).toList()) ==
    jsonEncode(right.map((profile) => profile.toJson()).toList());

final consumerSoundProfileProvider = StateNotifierProvider<
    ConsumerSoundProfileNotifier, List<ConsumerSoundProfile>>(
  (_) => ConsumerSoundProfileNotifier(),
);

final activeConsumerProfileProvider = Provider<ConsumerSoundProfile?>((ref) {
  final profiles = ref.watch(consumerSoundProfileProvider);
  try {
    return profiles.firstWhere((p) => p.isActive);
  } catch (_) {
    return null;
  }
});

final selectedConsumerProfileProvider = Provider<ConsumerSoundProfile?>((ref) {
  final profiles = ref.watch(consumerSoundProfileProvider);
  try {
    return profiles.firstWhere((profile) => profile.isSelected);
  } catch (_) {
    return null;
  }
});
