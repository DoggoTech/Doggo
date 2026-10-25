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
    this.locationConfirmed = true,
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

  /// El cuidador ya fijó su zona de servicio (sin ella no sale en el mapa).
  final bool locationConfirmed;

  bool offers(ServiceType type) => services.containsKey(type);

  SitterSummary copyWith({
    Map<ServiceType, int>? services,
    WeeklyAvailability? availability,
    double? ratingAvg,
    int? ratingCount,
    String? bio,
    bool? verified,
    LatLng? location,
    String? neighborhood,
    int? radiusKm,
    String? avatarUrl,
    bool? locationConfirmed,
  }) {
    return SitterSummary(
      id: id,
      name: name,
      neighborhood: neighborhood ?? this.neighborhood,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      radiusKm: radiusKm ?? this.radiusKm,
      services: services ?? this.services,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      verified: verified ?? this.verified,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      availability: availability ?? this.availability,
      locationConfirmed: locationConfirmed ?? this.locationConfirmed,
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
