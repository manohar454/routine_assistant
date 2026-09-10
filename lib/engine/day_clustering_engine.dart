import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/day_clustering_models.dart';

/// The day-type clustering engine. Runs lightweight k-means on your
/// accumulated DayVectors to discover recurring day archetypes, then
/// classifies each new morning using early signals so the rest of the
/// system can adapt proactively — before problems happen, not after.
///
/// Minimum data requirement: 14 days before clustering runs.
/// Below that, it returns a cold-start classification and falls back
/// to the Phase 1 rule-based behavior unchanged.
class DayClusteringEngine {
  DayClusteringEngine._internal();
  static final DayClusteringEngine instance = DayClusteringEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  static const int _minDaysForClustering = 14;
  static const int _numClusters = 3; // high-energy / average / rough
  static const int _maxIterations = 50;

  // ----------------------------------------------------------------
  // Daily vector creation
  // ----------------------------------------------------------------

  /// Call this each morning after wake is confirmed. Builds today's
  /// feature vector from last night's sleep log, the wake response
  /// latency just recorded, and yesterday's task completion rate.
  Future<DayVector> buildTodayVector({
    required double wakeLatencySeconds,
    required int scheduledTasksYesterday,
    required int completedTasksYesterday,
  }) async {
    final today = DateTime.now();

    // Sleep ratio: last night's sleep vs the configured floor.
    final lastNight = await _db.getLastNightSleep();
    final floorSetting = await _db.getSetting('sleep_floor_minutes');
    final floorMinutes =
        floorSetting != null ? int.tryParse(floorSetting) ?? 450 : 450;

    double sleepRatio = 0.5; // default if nothing logged
    if (lastNight != null) {
      sleepRatio = (lastNight.duration.inMinutes / floorMinutes).clamp(0.0, 1.0);
    }

    // Wake latency normalized to a 0-1 scale (0=instant, 1=took 10+ min).
    final wakeLatencyNormalized = (wakeLatencySeconds / 600).clamp(0.0, 1.0);

    // Completion rate yesterday.
    final completionRate = scheduledTasksYesterday == 0
        ? 0.5
        : (completedTasksYesterday / scheduledTasksYesterday).clamp(0.0, 1.0);

    // Calendar density — placeholder 0.3 (moderate) until calendar
    // integration is built in Phase 3. Using a neutral value here
    // means it doesn't unfairly skew clustering either way.
    const calendarDensity = 0.3;

    final vector = DayVector(
      id: const Uuid().v4(),
      date: DateTime(today.year, today.month, today.day),
      sleepRatio: sleepRatio,
      wakeLatencyNormalized: wakeLatencyNormalized,
      calendarDensity: calendarDensity,
      yesterdayCompletionRate: completionRate,
    );

    await _db.insertDayVector(vector);
    return vector;
  }

  // ----------------------------------------------------------------
  // K-means clustering (runs weekly, not every day)
  // ----------------------------------------------------------------

  /// Runs k-means on all accumulated DayVectors and persists the
  /// resulting clusters. Should be called once per week (or when
  /// enough new data has accumulated) — not on every app open.
  Future<List<DayCluster>> retrainClusters() async {
    final vectors = await _db.getRecentDayVectors(days: 90);

    if (vectors.length < _minDaysForClustering) {
      return []; // not enough data yet
    }

    final clusters = _kMeans(vectors);
    for (final cluster in clusters) {
      await _db.upsertDayCluster(cluster);
    }
    return clusters;
  }

  List<DayCluster> _kMeans(List<DayVector> vectors) {
    // Initialize centroids using k-means++ style seeding — pick first
    // centroid randomly, then pick subsequent ones weighted by distance
    // from existing centroids, so initial seeds spread out.
    final centroids = _initCentroids(vectors, _numClusters);
    final assignments = List<int>.filled(vectors.length, 0);

    for (int iter = 0; iter < _maxIterations; iter++) {
      bool changed = false;

      // Assignment step — assign each vector to its nearest centroid.
      for (int i = 0; i < vectors.length; i++) {
        double minDist = double.infinity;
        int bestCluster = 0;
        for (int k = 0; k < centroids.length; k++) {
          final dist = _euclideanDistSq(vectors[i].features, centroids[k]);
          if (dist < minDist) {
            minDist = dist;
            bestCluster = k;
          }
        }
        if (assignments[i] != bestCluster) {
          assignments[i] = bestCluster;
          changed = true;
        }
      }

      // Convergence check.
      if (!changed) break;

      // Update step — recompute each centroid as the mean of its members.
      for (int k = 0; k < _numClusters; k++) {
        final members =
            [for (int i = 0; i < vectors.length; i++) if (assignments[i] == k) i];
        if (members.isEmpty) continue;

        final newCentroid = List<double>.filled(vectors[0].features.length, 0);
        for (final idx in members) {
          final f = vectors[idx].features;
          for (int d = 0; d < f.length; d++) {
            newCentroid[d] += f[d];
          }
        }
        for (int d = 0; d < newCentroid.length; d++) {
          newCentroid[d] /= members.length;
        }
        centroids[k] = newCentroid;
      }
    }

    // Build DayCluster objects from the final centroids.
    return List.generate(_numClusters, (k) {
      final members =
          [for (int i = 0; i < vectors.length; i++) if (assignments[i] == k) i];
      return DayCluster(
        clusterId: k,
        centroid: centroids[k],
        inferredLabel: DayCluster.inferLabel(centroids[k]),
        memberCount: members.length,
      );
    });
  }

  List<List<double>> _initCentroids(List<DayVector> vectors, int k) {
    final centroids = <List<double>>[];
    // Pick first centroid at a fixed but non-trivial position.
    final seed = vectors[vectors.length ~/ 3].features;
    centroids.add(List.of(seed));

    for (int i = 1; i < k; i++) {
      // Pick the vector that's furthest from any existing centroid.
      double maxDist = -1;
      List<double> nextCentroid = vectors[0].features;
      for (final v in vectors) {
        double minDist = double.infinity;
        for (final c in centroids) {
          final d = _euclideanDistSq(v.features, c);
          if (d < minDist) minDist = d;
        }
        if (minDist > maxDist) {
          maxDist = minDist;
          nextCentroid = v.features;
        }
      }
      centroids.add(List.of(nextCentroid));
    }
    return centroids;
  }

  double _euclideanDistSq(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum;
  }

  // ----------------------------------------------------------------
  // Morning classification
  // ----------------------------------------------------------------

  /// Classifies today's vector against the learned clusters.
  /// Returns immediately — doesn't require network, runs on-device.
  Future<DayClassification> classifyToday(DayVector todayVector) async {
    final clusters = await _db.getAllDayClusters();

    if (clusters.isEmpty) {
      return const DayClassification(
        cluster: null,
        confidence: 0,
        hasEnoughData: false,
        reason: 'Still building your day-type model — '
            'needs about 2 weeks of data.',
      );
    }

    DayCluster nearest = clusters.first;
    double minDist = double.infinity;

    for (final cluster in clusters) {
      final dist = cluster.distanceTo(todayVector.features);
      if (dist < minDist) {
        minDist = dist;
        nearest = cluster;
      }
    }

    // Confidence: inversely proportional to distance.
    // A distance of 0 = perfect match = confidence 1.0.
    // A distance of 1 (max possible for normalized features) = 0 confidence.
    final confidence = (1 - minDist.clamp(0.0, 1.0));

    return DayClassification(
      cluster: nearest,
      confidence: confidence,
      hasEnoughData: true,
      reason: 'Today looks like a "${nearest.inferredLabel}" day '
          '(${(confidence * 100).toStringAsFixed(0)}% match). '
          'Sleep ratio: ${todayVector.sleepRatio.toStringAsFixed(2)}, '
          'wake latency: ${todayVector.wakeLatencyNormalized.toStringAsFixed(2)}.',
    );
  }
}