/// Datos privados de la contraparte de una reserva `accepted`.
class ContactInfo {
  const ContactInfo({required this.name, this.phone, this.address});

  final String name;
  final String? phone;
  final String? address;
}

/// Datos privados propios (solo los ve uno mismo y la contraparte aceptada).
class PrivateData {
  const PrivateData({this.phone, this.address});

  final String? phone;
  final String? address;
}
