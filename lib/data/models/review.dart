class Review {
  const Review({
    required this.id,
    required this.sitterId,
    required this.authorName,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String sitterId;
  final String authorName;
  final int rating;
  final DateTime createdAt;
  final String? comment;
}
