import 'dart:math' as math;

import 'models/service_type.dart';

/// Unidades cobradas, con la MISMA regla que el trigger de `bookings` en
/// schema.sql: guardería y hospedaje por día/noche (redondeando hacia arriba,
/// mínimo 1); el resto, una unidad por reserva.
int bookingUnits(ServiceType service, DateTime start, DateTime end) {
  if (service == ServiceType.daycare || service == ServiceType.boarding) {
    final hours = end.difference(start).inMinutes / 60;
    return math.max(1, (hours / 24).ceil());
  }
  return 1;
}

int bookingTotal(
  ServiceType service,
  int price,
  DateTime start,
  DateTime end,
) => price * bookingUnits(service, start, end);

/// Fin de la reserva según el servicio y la cantidad elegida:
/// paseo 30/60 min; guardería N días (de 10 h); hospedaje N noches; el resto 1 h.
DateTime bookingEnd(ServiceType service, DateTime start, {int amount = 1}) {
  switch (service) {
    case ServiceType.walk:
      return start.add(Duration(minutes: amount));
    case ServiceType.daycare:
      return start.add(Duration(hours: (amount - 1) * 24 + 10));
    case ServiceType.boarding:
      return start.add(Duration(days: amount));
    case ServiceType.homeVisit:
    case ServiceType.grooming:
    case ServiceType.training:
      return start.add(const Duration(hours: 1));
  }
}
