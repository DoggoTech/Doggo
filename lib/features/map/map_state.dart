import 'dart:async';

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
    service: v,
    maxPrice: maxPrice,
    maxDistanceKm: maxDistanceKm,
    minRating: minRating,
  );
  MapFilters withMaxPrice(int? v) => MapFilters(
    service: service,
    maxPrice: v,
    maxDistanceKm: maxDistanceKm,
    minRating: minRating,
  );
  MapFilters withMaxDistanceKm(int? v) => MapFilters(
    service: service,
    maxPrice: maxPrice,
    maxDistanceKm: v,
    minRating: minRating,
  );
  MapFilters withMinRating(double? v) => MapFilters(
    service: service,
    maxPrice: maxPrice,
    maxDistanceKm: maxDistanceKm,
    minRating: v,
  );
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

final mapFiltersProvider = NotifierProvider<MapFiltersNotifier, MapFilters>(
  MapFiltersNotifier.new,
);

class LocationState {
  const LocationState({this.point, this.tracking = false});

  /// Última posición conocida; `null` si no hay (se usa Bogotá centro).
  final LatLng? point;

  /// Si se está siguiendo la posición en tiempo real.
  final bool tracking;
}

/// Ubicación del usuario en tiempo real. Es `autoDispose`: al salir del mapa se
/// cancela el seguimiento, para no gastar batería con la pantalla fuera de uso.
class LocationNotifier extends Notifier<LocationState> {
  StreamSubscription<Position>? _subscription;

  @override
  LocationState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const LocationState();
  }

  /// Pide permiso, toma la posición actual y empieza a seguirla.
  /// Devuelve `false` si no hay permiso o falla.
  Future<bool> start() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _subscription?.cancel();
      state = LocationState(point: _toLatLng(first), tracking: true);
      _subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (p) => state = LocationState(point: _toLatLng(p), tracking: true),
            // Los errores pasajeros (señal débil, un timeout) son normales en un
            // celular en movimiento: se conserva la última posición y se sigue
            // escuchando. Solo se apaga si ya no hay permiso o servicio.
            onError: (Object e) {
              if (e is PermissionDeniedException ||
                  e is LocationServiceDisabledException) {
                stop();
              }
            },
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deja de seguir: el punto desaparece y la referencia vuelve a Bogotá.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    state = const LocationState();
  }

  LatLng _toLatLng(Position p) => LatLng(p.latitude, p.longitude);
}

final locationProvider =
    NotifierProvider.autoDispose<LocationNotifier, LocationState>(
      LocationNotifier.new,
    );

/// Posición del usuario (o `null`), para quien solo necesita el punto.
final userLocationProvider = Provider.autoDispose<LatLng?>(
  (ref) => ref.watch(locationProvider).point,
);

/// ¿El mapa acompaña al usuario mientras se mueve? Se apaga al arrastrar el mapa.
class FollowingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final followingProvider = NotifierProvider.autoDispose<FollowingNotifier, bool>(
  FollowingNotifier.new,
);

class SelectedSitterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedSitterIdProvider =
    NotifierProvider<SelectedSitterNotifier, String?>(
      SelectedSitterNotifier.new,
    );

final sittersProvider = FutureProvider.autoDispose<List<SitterSummary>>(
  (ref) => ref.watch(repositoryProvider).fetchSitters(),
);

class SitterView {
  const SitterView(this.sitter, this.distanceKm);
  final SitterSummary sitter;
  final double distanceKm;
}

/// Cuidadores que pasan los filtros, del más cercano al más lejano.
final visibleSittersProvider =
    Provider.autoDispose<AsyncValue<List<SitterView>>>((ref) {
      final filters = ref.watch(mapFiltersProvider);
      final origin = ref.watch(userLocationProvider) ?? bogotaCenter;
      return ref.watch(sittersProvider).whenData((all) {
        final views = <SitterView>[];
        for (final s in all) {
          if (filters.service != null && !s.offers(filters.service!)) continue;
          if (filters.maxPrice != null &&
              s.pinPrice(filters.service) > filters.maxPrice!) {
            continue;
          }
          if (filters.minRating != null &&
              (s.ratingAvg == null || s.ratingAvg! < filters.minRating!)) {
            continue;
          }
          final km = _distance.as(LengthUnit.Kilometer, origin, s.location);
          if (filters.maxDistanceKm != null && km > filters.maxDistanceKm!) {
            continue;
          }
          views.add(SitterView(s, km));
        }
        views.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return views;
      });
    });
