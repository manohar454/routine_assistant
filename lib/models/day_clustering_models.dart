/// Day-type clustering — Phase 2.
///
/// Instead of you labeling "today is a recovery day" or "this is a
/// high-energy day," the system discovers these archetypes automatically
/// from your own historical feature vectors and classifies each new
/// morning using early signals (sleep, weather proxy, calendar density).
///
/// Implementation: a simplified k-means style approach that's entirely
/// on-device, free, and works with the modest data volumes a single
/// person generates (30-90 days of history rather than millions of rows).
library;

/// A snapshot of features describing one day — this is the "input
/// vector" that gets clustered. All features are normalized 0-1 so
/// they're comparable in the distance calculation regardless of unit.
class DayVector {
  final String id;
  final DateTime date;

  /// 0 = no sleep logged, 1 = at or above your floor (7.5h default).
  final double sleepRatio;

  /// 0 = responded immediately, 1 = took maximum expected time.
  /// Higher = harder morning start.
  final double wakeLatencyNormalized;

  /// 0 = empty calendar, 1 = very dense (5+ fixed commitments).
  final double calendarDensity;

  /// 0-1 proxy for how many tasks were completed vs planned yesterday.
  /// Low completion yesterday is a predictor for today's quality.
  final double yesterdayCompletionRate;

  /// The cluster this day was assigned to after classification.
  /// Null until classified.
  int? assignedCluster;

  DayVector({
    required this.id,
    required this.date,
    required this.sleepRatio,
    required this.wakeLatencyNormalized,
    required this.calendarDensity,
    required this.yesterdayCompletionRate,
    this.assignedCluster,
  });

  List<double> get features => [
        sleepRatio,
        wakeLatencyNormalized,
        calendarDensity,
        yesterdayCompletionRate,
      ];

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'sleepRatio': sleepRatio,
        'wakeLatencyNormalized': wakeLatencyNormalized,
        'calendarDensity': calendarDensity,
        'yesterdayCompletionRate': yesterdayCompletionRate,
        'assignedCluster': assignedCluster,
      };

  factory DayVector.fromMap(Map<String, dynamic> map) => DayVector(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
        sleepRatio: (map['sleepRatio'] as num?)?.toDouble() ?? 0.0,
        wakeLatencyNormalized:
            (map['wakeLatencyNormalized'] as num?)?.toDouble() ?? 0.0,
        calendarDensity:
            (map['calendarDensity'] as num?)?.toDouble() ?? 0.0,
        yesterdayCompletionRate:
            (map['yesterdayCompletionRate'] as num?)?.toDouble() ?? 0.0,
        assignedCluster:
            (map['assignedCluster'] as num?)?.toInt(),
      );
}

/// A discovered day archetype — what the clustering algorithm converges
/// on after enough data. Labels are inferred from centroid values, not
/// hardcoded, so they reflect actual patterns in your data.
class DayCluster {
  final int clusterId;
  List<double> centroid; // mean feature vector for this cluster
  String inferredLabel; // e.g. "high-energy", "rough", "average"
  int memberCount;

  DayCluster({
    required this.clusterId,
    required this.centroid,
    required this.inferredLabel,
    required this.memberCount,
  });

  /// Euclidean distance from this cluster's centroid to a feature vector.
  double distanceTo(List<double> features) {
    double sum = 0;

    final length =
        centroid.length < features.length ? centroid.length : features.length;

    for (int i = 0; i < length; i++) {
      final diff = centroid[i] - features[i];
      sum += diff * diff;
    }

    return sum; // squared distance is fine for comparison
  }

  Map<String, dynamic> toMap() => {
        'clusterId': clusterId,
        'centroid': centroid.join(','),
        'inferredLabel': inferredLabel,
        'memberCount': memberCount,
      };

  factory DayCluster.fromMap(Map<String, dynamic> map) => DayCluster(
        clusterId: (map['clusterId'] as num?)?.toInt() ?? 0,

        // Defensive centroid parsing.
        // Handles null, empty, invalid, or malformed values safely.
        centroid: (map['centroid'] as String? ?? '0,0,0,0')
            .split(',')
            .map((s) => double.tryParse(s.trim()) ?? 0.0)
            .toList(),

        inferredLabel: map['inferredLabel'] as String? ?? 'average',
        memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      );

  /// Infers a human-readable label from the centroid values.
  /// sleepRatio high + wakeLatency low = high energy.
  /// sleepRatio low + wakeLatency high = rough day.
  static String inferLabel(List<double> centroid) {
    if (centroid.length < 4) {
      return 'average';
    }

    final sleep = centroid[0]; // sleepRatio — higher is better
    final wakeLatency = centroid[1]; // higher = harder wake
    final completion = centroid[3]; // higher is better

    if (sleep > 0.8 &&
        wakeLatency < 0.3 &&
        completion > 0.75) {
      return 'high-energy';
    } else if (sleep < 0.5 || wakeLatency > 0.7) {
      return 'rough';
    } else if (completion > 0.7) {
      return 'productive';
    } else {
      return 'average';
    }
  }
}

/// Classification result for today — includes the matched cluster,
/// a confidence score (inverse of distance to centroid), and whether
/// there was enough data to cluster reliably.
class DayClassification {
  final DayCluster? cluster;
  final double confidence; // 0-1, higher is more confident
  final bool hasEnoughData;
  final String reason;

  const DayClassification({
    required this.cluster,
    required this.confidence,
    required this.hasEnoughData,
    required this.reason,
  });
}