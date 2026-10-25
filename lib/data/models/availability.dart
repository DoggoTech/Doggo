/// Franja del día en la que el cuidador puede EMPEZAR un servicio
/// (minutos desde la medianoche, ambos extremos incluidos).
class DayWindow {
  const DayWindow(this.startMinute, this.endMinute);

  final int startMinute;
  final int endMinute;

  bool contains(int minute) => minute >= startMinute && minute <= endMinute;

  @override
  bool operator ==(Object other) =>
      other is DayWindow &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(startMinute, endMinute);
}

const weekdayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Horario semanal del cuidador. La clave es el día ISO (1 = lunes … 7 =
/// domingo, igual que `DateTime.weekday`); un día ausente = no atiende.
class WeeklyAvailability {
  const WeeklyAvailability(this.days);

  final Map<int, DayWindow> days;

  /// Por defecto: todos los días de 7:00 a 19:00 (la franja de la hoja de reserva).
  static const standard = WeeklyAvailability({
    1: DayWindow(420, 1140),
    2: DayWindow(420, 1140),
    3: DayWindow(420, 1140),
    4: DayWindow(420, 1140),
    5: DayWindow(420, 1140),
    6: DayWindow(420, 1140),
    7: DayWindow(420, 1140),
  });

  bool allows(DateTime start) {
    final w = days[start.weekday];
    return w != null && w.contains(start.hour * 60 + start.minute);
  }

  WeeklyAvailability withDay(int weekday, DayWindow? window) {
    final next = Map<int, DayWindow>.of(days);
    if (window == null) {
      next.remove(weekday);
    } else {
      next[weekday] = window;
    }
    return WeeklyAvailability(next);
  }
}
