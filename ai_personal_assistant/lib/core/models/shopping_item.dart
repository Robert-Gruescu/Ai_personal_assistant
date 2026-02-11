import 'package:hive/hive.dart';

part 'shopping_item.g.dart';

@HiveType(typeId: 3)
class ShoppingItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String quantity;

  @HiveField(3)
  String? category;

  @HiveField(4)
  bool isPurchased;

  @HiveField(5)
  String? notes;

  @HiveField(6)
  double? priceEstimate;

  @HiveField(7)
  DateTime createdAt;

  ShoppingItem({
    required this.id,
    required this.name,
    this.quantity = '1',
    this.category,
    this.isPurchased = false,
    this.notes,
    this.priceEstimate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  ShoppingItem copyWith({
    String? id,
    String? name,
    String? quantity,
    String? category,
    bool? isPurchased,
    String? notes,
    double? priceEstimate,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      isPurchased: isPurchased ?? this.isPurchased,
      notes: notes ?? this.notes,
      priceEstimate: priceEstimate ?? this.priceEstimate,
      createdAt: createdAt,
    );
  }
}
