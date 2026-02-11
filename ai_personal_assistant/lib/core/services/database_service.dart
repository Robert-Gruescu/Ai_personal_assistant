import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/conversation.dart';
import '../models/task.dart';
import '../models/shopping_item.dart';
import '../models/calendar_event.dart';
import '../models/agent_action.dart';

/// Database service for local data storage using Hive
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static const String _conversationsBox = 'conversations';
  static const String _tasksBox = 'tasks';
  static const String _shoppingBox = 'shopping';
  static const String _calendarBox = 'calendar';
  static const String _actionsBox = 'actions';

  final _uuid = const Uuid();

  bool _isInitialized = false;

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TaskAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ShoppingItemAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(CalendarEventAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(AgentActionAdapter());
    }

    // Open boxes
    await Hive.openBox<Conversation>(_conversationsBox);
    await Hive.openBox<Task>(_tasksBox);
    await Hive.openBox<ShoppingItem>(_shoppingBox);
    await Hive.openBox<CalendarEvent>(_calendarBox);
    await Hive.openBox<AgentAction>(_actionsBox);

    _isInitialized = true;
    print('✅ Database initialized');
  }

  String generateId() => _uuid.v4();

  // ============ CONVERSATIONS ============

  Box<Conversation> get _conversationsBoxInstance =>
      Hive.box<Conversation>(_conversationsBox);

  Future<Conversation> createConversation({String? title}) async {
    final conversation = Conversation(
      id: generateId(),
      title: title ?? 'Conversație Nouă',
    );
    await _conversationsBoxInstance.put(conversation.id, conversation);
    return conversation;
  }

  Future<Conversation?> getConversation(String id) async {
    return _conversationsBoxInstance.get(id);
  }

  Future<List<Conversation>> getAllConversations() async {
    final conversations = _conversationsBoxInstance.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  Future<void> addMessageToConversation(
    String conversationId,
    String role,
    String content, {
    String? audioPath,
  }) async {
    final conversation = _conversationsBoxInstance.get(conversationId);
    if (conversation != null) {
      final message = Message(
        id: generateId(),
        role: role,
        content: content,
        audioPath: audioPath,
      );
      conversation.addMessage(message);
      await conversation.save();
    }
  }

  Future<void> deleteConversation(String id) async {
    await _conversationsBoxInstance.delete(id);
  }

  // ============ TASKS ============

  Box<Task> get _tasksBoxInstance => Hive.box<Task>(_tasksBox);

  Future<Task> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    DateTime? reminderDate,
    int priority = 2,
    String? category,
  }) async {
    final task = Task(
      id: generateId(),
      title: title,
      description: description,
      dueDate: dueDate,
      reminderDate: reminderDate,
      priority: priority,
      category: category,
    );
    await _tasksBoxInstance.put(task.id, task);
    return task;
  }

  Future<List<Task>> getAllTasks({bool? completed, String? category}) async {
    var tasks = _tasksBoxInstance.values.toList();

    if (completed != null) {
      tasks = tasks.where((t) => t.isCompleted == completed).toList();
    }
    if (category != null) {
      tasks = tasks.where((t) => t.category == category).toList();
    }

    tasks.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });

    return tasks;
  }

  Future<Task?> getTask(String id) async {
    return _tasksBoxInstance.get(id);
  }

  Future<Task?> findTaskByTitle(String titleQuery) async {
    final tasks = _tasksBoxInstance.values.toList();
    final query = titleQuery.toLowerCase();
    return tasks.firstWhere(
      (t) => t.title.toLowerCase().contains(query),
      orElse: () => Task(id: '', title: ''),
    );
  }

  Future<void> updateTask(Task task) async {
    task.updatedAt = DateTime.now();
    await task.save();
  }

  Future<void> completeTask(String id) async {
    final task = _tasksBoxInstance.get(id);
    if (task != null) {
      task.isCompleted = true;
      task.updatedAt = DateTime.now();
      await task.save();
    }
  }

  Future<void> deleteTask(String id) async {
    await _tasksBoxInstance.delete(id);
  }

  // ============ SHOPPING ITEMS ============

  Box<ShoppingItem> get _shoppingBoxInstance =>
      Hive.box<ShoppingItem>(_shoppingBox);

  Future<ShoppingItem> createShoppingItem({
    required String name,
    String quantity = '1',
    String? category,
    String? notes,
    double? priceEstimate,
  }) async {
    final item = ShoppingItem(
      id: generateId(),
      name: name,
      quantity: quantity,
      category: category,
      notes: notes,
      priceEstimate: priceEstimate,
    );
    await _shoppingBoxInstance.put(item.id, item);
    return item;
  }

  Future<List<ShoppingItem>> getAllShoppingItems({bool? purchased}) async {
    var items = _shoppingBoxInstance.values.toList();

    if (purchased != null) {
      items = items.where((i) => i.isPurchased == purchased).toList();
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<ShoppingItem?> getShoppingItem(String id) async {
    return _shoppingBoxInstance.get(id);
  }

  Future<ShoppingItem?> findShoppingItemByName(String nameQuery) async {
    final items = _shoppingBoxInstance.values.toList();
    final query = nameQuery.toLowerCase();
    try {
      return items.firstWhere((i) => i.name.toLowerCase().contains(query));
    } catch (e) {
      return null;
    }
  }

  Future<void> updateShoppingItem(ShoppingItem item) async {
    await item.save();
  }

  Future<void> markShoppingItemPurchased(String id) async {
    final item = _shoppingBoxInstance.get(id);
    if (item != null) {
      item.isPurchased = true;
      await item.save();
    }
  }

  Future<void> deleteShoppingItem(String id) async {
    await _shoppingBoxInstance.delete(id);
  }

  Future<double> getShoppingListTotal() async {
    final items = await getAllShoppingItems(purchased: false);
    double total = 0.0;
    for (final item in items) {
      total += item.priceEstimate ?? 0.0;
    }
    return total;
  }

  // ============ CALENDAR EVENTS ============

  Box<CalendarEvent> get _calendarBoxInstance =>
      Hive.box<CalendarEvent>(_calendarBox);

  Future<CalendarEvent> createCalendarEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? meetLink,
    String? attendeeEmail,
    String? attendeeName,
    DateTime? reminderTime,
  }) async {
    final event = CalendarEvent(
      id: generateId(),
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      meetLink: meetLink,
      attendeeEmail: attendeeEmail,
      attendeeName: attendeeName,
      reminderTime: reminderTime,
    );
    await _calendarBoxInstance.put(event.id, event);
    return event;
  }

  Future<List<CalendarEvent>> getAllCalendarEvents({String? status}) async {
    var events = _calendarBoxInstance.values.toList();

    if (status != null) {
      events = events.where((e) => e.status == status).toList();
    }

    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  Future<List<CalendarEvent>> getUpcomingEvents({int days = 7}) async {
    final now = DateTime.now();
    final endDate = now.add(Duration(days: days));
    final events = _calendarBoxInstance.values.where((e) {
      return e.startTime.isAfter(now) &&
          e.startTime.isBefore(endDate) &&
          e.status == 'scheduled';
    }).toList();

    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  Future<CalendarEvent?> getCalendarEvent(String id) async {
    return _calendarBoxInstance.get(id);
  }

  Future<void> updateCalendarEvent(CalendarEvent event) async {
    event.updatedAt = DateTime.now();
    await event.save();
  }

  Future<void> cancelCalendarEvent(String id) async {
    final event = _calendarBoxInstance.get(id);
    if (event != null) {
      event.status = 'cancelled';
      event.updatedAt = DateTime.now();
      await event.save();
    }
  }

  Future<void> deleteCalendarEvent(String id) async {
    await _calendarBoxInstance.delete(id);
  }

  // ============ AGENT ACTIONS ============

  Box<AgentAction> get _actionsBoxInstance =>
      Hive.box<AgentAction>(_actionsBox);

  Future<AgentAction> logAction({
    required String actionType,
    String? target,
    String? content,
  }) async {
    final action = AgentAction(
      id: generateId(),
      actionType: actionType,
      target: target,
      content: content,
    );
    await _actionsBoxInstance.put(action.id, action);
    return action;
  }

  Future<List<AgentAction>> getActionHistory({
    String? actionType,
    String? status,
    int limit = 20,
  }) async {
    var actions = _actionsBoxInstance.values.toList();

    if (actionType != null) {
      actions = actions.where((a) => a.actionType == actionType).toList();
    }
    if (status != null) {
      actions = actions.where((a) => a.status == status).toList();
    }

    actions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return actions.take(limit).toList();
  }

  Future<void> updateAction(AgentAction action) async {
    await action.save();
  }

  // ============ UTILITY ============

  Future<void> clearAllData() async {
    await _conversationsBoxInstance.clear();
    await _tasksBoxInstance.clear();
    await _shoppingBoxInstance.clear();
    await _calendarBoxInstance.clear();
    await _actionsBoxInstance.clear();
  }

  Future<void> close() async {
    await Hive.close();
  }
}
