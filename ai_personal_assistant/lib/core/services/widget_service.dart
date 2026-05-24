import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';

class WidgetService {
  static final WidgetService _instance = WidgetService._internal();
  factory WidgetService() => _instance;
  WidgetService._internal();

  static const String _androidWidgetName = 'AsisWidgetProvider';

  final DatabaseService _db = DatabaseService();

  Future<void> initialize() async {
    // setAppGroupId e doar pentru iOS - pe Android nu e necesar
    print('✅ WidgetService initialized');
  }

  Future<void> updateWidget() async {
    try {
      final tasks = await _db.getAllTasks(completed: false);
      final shoppingItems = await _db.getAllShoppingItems(purchased: false);

      String tasksText;
      if (tasks.isEmpty) {
        tasksText = 'Niciun task activ 🎉';
      } else {
        final sorted = [...tasks]
          ..sort((a, b) => b.priority.compareTo(a.priority));
        final displayed = sorted.take(3).toList();
        tasksText = displayed
            .map((t) {
              final priority = t.priority == 3
                  ? '🔴'
                  : t.priority == 2
                  ? '🟡'
                  : '🟢';
              return '$priority ${t.title}';
            })
            .join('\n');
        if (tasks.length > 3) {
          tasksText += '\n+${tasks.length - 3} mai multe...';
        }
      }

      String shoppingText;
      if (shoppingItems.isEmpty) {
        shoppingText = 'Lista este goală 🛍️';
      } else {
        final displayed = shoppingItems.take(3).toList();
        shoppingText = displayed
            .map((i) => '• ${i.name} (${i.quantity})')
            .join('\n');
        if (shoppingItems.length > 3) {
          shoppingText += '\n+${shoppingItems.length - 3} mai multe...';
        }
      }

      final updatedText =
          'Actualizat: ${DateFormat('HH:mm').format(DateTime.now())}';

      await HomeWidget.saveWidgetData<String>('widget_tasks', tasksText);
      await HomeWidget.saveWidgetData<String>('widget_shopping', shoppingText);
      await HomeWidget.saveWidgetData<String>('widget_updated', updatedText);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);

      print(
        '✅ Widget actualizat: ${tasks.length} task-uri, ${shoppingItems.length} produse',
      );
    } catch (e) {
      print('⚠️ Eroare la actualizarea widget-ului: $e');
    }
  }
}
