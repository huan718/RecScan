class Purchase {
  final int? id;
  final String name;
  final String date;
  final double price;
  final String category;
  final String? imagePath;

  Purchase({
    this.id,
    required this.name,
    required this.date,
    required this.price,
    required this.category,
    this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date,
      'price': price,
      'category': category,
      'imagePath': imagePath,
    };
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'],
      name: map['name'],
      date: map['date'],
      price: map['price'],
      category: map['category'],
      imagePath: map['imagePath'],
    );
  }
} 