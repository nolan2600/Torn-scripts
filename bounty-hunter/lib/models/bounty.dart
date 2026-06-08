class BountyEntry {
  final int targetId;
  final String targetName;
  final int targetLevel;
  final int reward;
  final int bountyCount;
  final double? ff;
  final String? bsEstimate;
  final String statusState;
  final int hospUntil;
  final bool? revivable;
  final int? factionId;
  final bool inFactionWar;

  const BountyEntry({
    required this.targetId,
    required this.targetName,
    required this.targetLevel,
    required this.reward,
    this.bountyCount = 1,
    this.ff,
    this.bsEstimate,
    this.statusState = 'Okay',
    this.hospUntil = 0,
    this.revivable,
    this.factionId,
    this.inFactionWar = false,
  });

  int get hospRemaining =>
      hospUntil > 0
          ? (hospUntil - DateTime.now().millisecondsSinceEpoch ~/ 1000)
              .clamp(0, 999999)
          : 0;

  BountyEntry copyWith({
    double? ff,
    String? bsEstimate,
    String? statusState,
    int? hospUntil,
    bool? revivable,
    int? factionId,
    bool? inFactionWar,
  }) =>
      BountyEntry(
        targetId: targetId,
        targetName: targetName,
        targetLevel: targetLevel,
        reward: reward,
        bountyCount: bountyCount,
        ff: ff ?? this.ff,
        bsEstimate: bsEstimate ?? this.bsEstimate,
        statusState: statusState ?? this.statusState,
        hospUntil: hospUntil ?? this.hospUntil,
        revivable: revivable ?? this.revivable,
        factionId: factionId ?? this.factionId,
        inFactionWar: inFactionWar ?? this.inFactionWar,
      );
}
