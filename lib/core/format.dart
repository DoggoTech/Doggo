/// Pesos colombianos con punto de miles: 25000 -> $25.000
String formatCop(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return '\$$out';
}

/// 0.4 -> "400 m", 2.34 -> "2,3 km"
String formatKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// 4.9 -> "4,9"
String formatRating(double rating) =>
    rating.toStringAsFixed(1).replaceAll('.', ',');

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "sáb 25 oct"
String formatDay(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "Hoy", "Mañana" o "lun 27 oct".
String formatDayChip(DateTime day, DateTime today) {
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(today.year, today.month, today.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  return formatDay(day);
}

/// "9:00"
String formatTime(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// "sáb 25 oct, 9:00"
String formatDateTime(DateTime d) => '${formatDay(d)}, ${formatTime(d)}';
