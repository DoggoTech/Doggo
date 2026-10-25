enum DogSize {
  small('Pequeño'),
  medium('Mediano'),
  large('Grande'),
  giant('Gigante');

  const DogSize(this.label);
  final String label;
}

class Dog {
  const Dog({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.size,
    this.breed,
  });

  final String id;
  final String ownerId;
  final String name;
  final DogSize size;
  final String? breed;
}
