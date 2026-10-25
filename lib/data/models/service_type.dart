enum ServiceType {
  walk('Paseo', 'por paseo'),
  daycare('Guardería de día', 'por día'),
  boarding('Hospedaje nocturno', 'por noche'),
  homeVisit('Visita a domicilio', 'por visita'),
  grooming('Baño y peluquería', 'por sesión'),
  training('Entrenamiento básico', 'por sesión');

  const ServiceType(this.label, this.unit);
  final String label;
  final String unit;
}
