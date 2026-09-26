import 'dart:async';
import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';

/// Phase 3 — Calendar density signal.
///
/// Reads today's calendar events (via the device's calendar app) and
/// computes a normalised density score in [0.0, 1.0]:
///   0.0 = completely free day
///   1.0 = 8+ hours of events (fully booked)
///
/// If calendar permission is denied or no calendars are available, the
/// service returns the neutral fallback value (0.3) so the clustering
/// engine is unaffected.
///
/// Usage:
///   final density = await CalendarService.instance.todayDensity();
///   // Pass to DayClusteringEngine.buildTodayVector as calendarDensity
class CalendarService {
  CalendarService._internal();
  static final CalendarService instance = CalendarService._internal();

  static const double _fallback = 0.3;
  static const int _fullyBookedMinutes = 8 * 60; // 8 h → density 1.0

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a 0.0–1.0 calendar density for today.
  /// Returns [_fallback] on any error or permission denial.
  Future<double> todayDensity() async {
    try {
      final granted = await _requestPermission();
      if (!granted) return _fallback;

      final calendars = await _fetchCalendars();
      if (calendars.isEmpty) return _fallback;

      final totalMinutes = await _sumEventMinutesToday(calendars);
      return (totalMinutes / _fullyBookedMinutes).clamp(0.0, 1.0);
    } catch (_) {
      return _fallback;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<bool> _requestPermission() async {
    final status = await Permission.calendar.status;
    if (status.isGranted) return true;

    final result = await Permission.calendar.request();
    return result.isGranted;
  }

  Future<List<Calendar>> _fetchCalendars() async {
    final result = await _plugin.retrieveCalendars();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    return [];
  }

  Future<int> _sumEventMinutesToday(List<Calendar> calendars) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 0, 0, 0);
    final end = DateTime(today.year, today.month, today.day, 23, 59, 59);

    int totalMinutes = 0;

    for (final calendar in calendars) {
      final result = await _plugin.retrieveEvents(
        calendar.id!,
        RetrieveEventsParams(startDate: start, endDate: end),
      );

      if (!result.isSuccess || result.data == null) continue;

      for (final event in result.data!) {
        if (event.start == null || event.end == null) continue;
        if (event.isAllDay ?? false) {
          // All-day events count as a fixed 4 hours.
          totalMinutes += 240;
        } else {
          final dur = event.end!.difference(event.start!).inMinutes;
          totalMinutes += dur.clamp(0, _fullyBookedMinutes);
        }
      }
    }

    return totalMinutes;
  }
}
