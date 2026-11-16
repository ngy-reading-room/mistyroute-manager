/// Small formatting helpers for the dashboard.
/// All sizes come from the panel API as bytes; we display GB with 2 decimals.
library;

String formatGb(int bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  final kb = bytes / 1024;
  if (kb >= 1) return '${kb.toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Bytes-per-second (live network speed) as e.g. "8.42 MB/s".
String formatSpeed(int bytesPerSec) {
  final mb = bytesPerSec / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(2)} MB/s';
  final kb = bytesPerSec / 1024;
  if (kb >= 1) return '${kb.toStringAsFixed(1)} KB/s';
  return '$bytesPerSec B/s';
}

/// "2026-12-11" — always ISO so it can never be misread as M-D-Y.
String formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// "5 days left" / "Expires today" / "Expired 3 days ago" / "No expiry".
String daysLeftText(DateTime? expiry) {
  if (expiry == null) return 'No expiry';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final exp = DateTime(expiry.year, expiry.month, expiry.day);
  final days = exp.difference(today).inDays;
  if (days < 0) return 'Expired ${-days}d ago';
  if (days == 0) return 'Expires today';
  if (days == 1) return '1 day left';
  return '$days days left';
}

/// "5d 3h" uptime.
String formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
