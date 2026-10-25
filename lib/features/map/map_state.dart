import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/service_type.dart';
import '../../data/models/sitter_summary.dart';
import '../../data/providers.dart';

/// Centro de Bogotá: punto de referencia cuando no hay permiso de ubicación.
const bogotaCenter = LatLng(4.6533, -74.0836);

// `roundResult: false`: por defecto latlong2 redondea a kilómetros enteros.
const _distance = Distance(roundResult: false);

class MapFilters {
  const MapFilters({
    this.service,
    this.maxPrice,
    this.maxDistanceKm,
    this.minRating,
  });

  final ServiceType? service;
  final int? maxPrice;
  final int? maxDistanceKm;
  final double? minRating;

  /// Cantidad de filtros avanzados activos (el servicio va en los chips).
  int get advancedCount =>
      [maxPrice, maxDistanceKm, minRating].where((v) => v != null).length;

  bool get isEmpty => service == null && advancedCount == 0;

  MapFilters withService(ServiceType? v) => MapFilters(
      service: v, maxPrice: maxPrice, maxDistanceKm: maxDistanceKm, minRating: minRating);
  MapFilters withMaxPrice(int? v) => MapFilters(
      service: service, maxPrice: v, maxDistanceKm: maxDistanceKm, minRating: minRating);
  MapFilters withMaxDistanceKm(int? v) => MapFilters(
      service: service, maxPrice: maxPrice, maxDistanceKm: v, minRating: minRating);
  MapFilters withMinRating(double? v) => MapFilters(
      service: service, maxPrice: maxPrice, maxDistanceKm: maxDistanceKm, minRating: v);
}

class MapFiltersNotifier extends Notifier<MapFilters> {
  @override
  MapFilters build() => const MapFilters();

  void setService(ServiceType? v) => state = state.withService(v);
  void setMaxPrice(int? v) => state = state.withMaxPrice(v);
  void setMaxDistanceKm(int? v) => state = state.withMaxDistanceKm(v);
  void setMinRating(double? v) => state = state.withMinRating(v);
  void clear() => state = const MapFilters();
}

final mapFiltersProvider =
    NotifierProvider<MapFiltersNotifier, MapFilters>(MapFiltersNotifier.new);

/// Ubicación real del usuario, o `null` si no la dio (se usa Bogotá centro).
class UserLocationNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  /// Pide la ubicación. Devuelve `false` si no hay permiso o falla.
  Future<bool> locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      state = LatLng(position.latitude, position.longitude);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final userLocationProvider =
    NotifierProvider<UserLocationNotifier, LatLng?>(UserLocationNotifier.new);

class SelectedSitterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedSitterIdProvider =
    NotifierProvider<SelectedSitterNotifier, String?>(SelectedSitterNotifier.new);

final sittersProvider = FutureProvider<List<SitterSummary>>(
  (ref) => ref.watch(repositoryProvider).fetchSitters(),
);

class SitterView {
  const SitterView(this.sitter, this.distanceKm);
  final SitterSummary sitter;
  final double distanceKm;
}

/// Cuidadores que pasan los filtros, del más cercano al más lejano.
final visibleSittersProvider = Provider<AsyncValue<List<SitterView>>>((ref) {
  final filters = ref.watch(mapFiltersProvider);
  final origin = ref.watch(userLocationProvider) ?? bogotaCenter;
  return ref.watch(sittersProvider).whenData((all) {
    final views = <SitterView>[];
    for (final s in all) {
      if (filters.service != null && !s.offers(filters.service!)) continue;
      if (filters.maxPrice != null && s.pinPrice(filters.service) > filters.maxPrice!) {
        continue;
      }
      if (filters.minRating != null &&
          (s.ratingAvg == null || s.ratingAvg! < filters.minRating!)) {
        continue;
      }
      final km = _distance.as(LengthUnit.Kilometer, origin, s.location);
      if (filters.maxDistanceKm != null && km > filters.maxDistanceKm!) continue;
      views.add(SitterView(s, km));
    }
    views.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return views;
  });
});
