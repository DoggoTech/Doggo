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
