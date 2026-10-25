import 'package:latlong2/latlong.dart';

import 'availability.dart';
import 'service_type.dart';

/// Un cuidador aprobado tal como se muestra en el mapa y la lista.
/// La ubicación es la APROXIMADA (desplazada 200–300 m), nunca la exacta.
class SitterSummary {
  const SitterSummary({
    required this.id,
    required this.name,
    required this.neighborhood,
    required this.bio,
    required this.location,
    required this.radiusKm,
    required this.services,
    this.avatarUrl,
    this.verified = false,
    this.ratingAvg,
    this.ratingCount = 0,
    this.availability = WeeklyAvailability.standard,
  });

  final String id;
  final String name;
  final String neighborhood;
  final String bio;
  final LatLng location;
  final int radiusKm;

  /// Precio en COP de cada servicio activo.
  final Map<ServiceType, int> services;
  final String? avatarUrl;
  final bool verified;
  final double? ratingAvg;
  final int ratingCount;

  /// Cuándo puede empezar servicios (horario semanal).
  final WeeklyAvailability availability;

  bool offers(ServiceType type) => services.containsKey(type);

  SitterSummary copyWith({
    Map<ServiceType, int>? services,
    WeeklyAvailability? availability,
  }) {
    return SitterSummary(
      id: id,
      name: name,
      neighborhood: neighborhood,
      bio: bio,
      location: location,
      radiusKm: radiusKm,
      services: services ?? this.services,
      avatarUrl: avatarUrl,
      verified: verified,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      availability: availability ?? this.availability,
    );
  }

  /// Precio que muestra el pin: el más bajo del servicio filtrado; sin filtro,
  /// el del paseo (o el más bajo que ofrezca si no hace paseos).
  int pinPrice(ServiceType? filter) {
    if (filter != null) return services[filter]!;
    return services[ServiceType.walk] ??
        services.values.reduce((a, b) => a < b ? a : b);
  }

  /// Etiqueta del servicio al que corresponde [pinPrice].
  ServiceType pinService(ServiceType? filter) {
    if (filter != null) return filter;
    if (services.containsKey(ServiceType.walk)) return ServiceType.walk;
    return services.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }
}
