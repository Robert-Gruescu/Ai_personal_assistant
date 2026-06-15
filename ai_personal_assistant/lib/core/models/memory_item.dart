import 'package:hive/hive.dart';

part 'memory_item.g.dart';

/// Un fapt pe care asistentul îl reține despre utilizator (memorie de lungă durată).
/// Ex: "Pe soția mea o cheamă Ana", "Sunt alergic la arahide", "Beau cafea fără zahăr".
/// Memoria este controlată de utilizator (explicit "ține minte că...") și
/// stocată exclusiv local, în Hive. NU implică apeluri AI suplimentare:
/// faptele relevante se injectează în contextul aceluiași apel Gemini făcut oricum.
@HiveType(typeId: 6)
class MemoryItem extends HiveObject {
  @HiveField(0)
  String id;

  /// Faptul propriu-zis, formulat scurt și clar (ex: "Pe soția mea o cheamă Ana").
  @HiveField(1)
  String content;

  /// Categorie opțională: preferinta / persoana / fapt / rutina / altele.
  @HiveField(2)
  String? category;

  /// Cuvinte-cheie pentru regăsirea relevantă (fără AI), extrase din conținut.
  @HiveField(3)
  List<String> keywords;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  MemoryItem({
    required this.id,
    required this.content,
    this.category,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : keywords = keywords ?? const [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  MemoryItem copyWith({
    String? content,
    String? category,
    List<String>? keywords,
  }) {
    return MemoryItem(
      id: id,
      content: content ?? this.content,
      category: category ?? this.category,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
