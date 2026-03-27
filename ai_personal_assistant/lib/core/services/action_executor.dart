import '../services/database_service.dart';
import '../services/email_service.dart';
import '../services/search_service.dart';
import '../services/notification_service.dart';
import '../services/device_calendar_service.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

/// Action result from executing an action
class ActionResult {
  final bool success;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;

  ActionResult({required this.success, this.message, this.error, this.data});

  factory ActionResult.success(String message, {Map<String, dynamic>? data}) =>
      ActionResult(success: true, message: message, data: data);

  factory ActionResult.error(String errorMessage) =>
      ActionResult(success: false, error: errorMessage);

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'error': error,
    if (data != null) ...data!,
  };
}

/// Action Executor - Handles execution of AI-detected actions
class ActionExecutor {
  static final ActionExecutor _instance = ActionExecutor._internal();
  factory ActionExecutor() => _instance;
  ActionExecutor._internal();

  final DatabaseService _db = DatabaseService();
  final EmailService _email = EmailService();
  final SearchService _search = SearchService();
  final NotificationService _notification = NotificationService();
  final DeviceCalendarService _deviceCalendar = DeviceCalendarService();

  /// Execute an action based on detected intent
  Future<ActionResult> execute(
    String intent,
    Map<String, dynamic>? actionData,
  ) async {
    print('🚀 Executing action: $intent with data: $actionData');

    final handlers = {
      'add_task': _addTask,
      'list_tasks': _listTasks,
      'complete_task': _completeTask,
      'delete_task': _deleteTask,
      'add_shopping_item': _addShoppingItem,
      'list_shopping': _listShopping,
      'remove_shopping_item': _removeShoppingItem,
      'send_email': _sendEmail,
      'read_emails': _readEmails,
      'read_last_email': _readLastEmail,
      'search_emails': _searchEmails,
      'search_internet': _searchInternet,
      'compare_shopping_prices': _compareShoppingPrices,
      'schedule_meeting': _scheduleMeeting,
      'add_calendar_event': _addCalendarEvent,
      'list_calendar_events': _listCalendarEvents,
      'cancel_calendar_event': _cancelCalendarEvent,
    };

    final handler = handlers[intent];
    if (handler != null) {
      return await handler(actionData ?? {});
    }

    return ActionResult.error('Acțiune necunoscută: $intent');
  }

  // ============ TASK ACTIONS ============

  Future<ActionResult> _addTask(Map<String, dynamic> data) async {
    try {
      // Check if data contains a 'tasks' list (multiple tasks)
      if (data.containsKey('tasks') && data['tasks'] is List) {
        final tasksList = data['tasks'] as List;
        final addedTasks = <String>[];
        for (final taskData in tasksList) {
          final taskMap = taskData as Map<String, dynamic>;
          final task = await _db.createTask(
            title: taskMap['title'] ?? 'Task fără titlu',
            description: taskMap['description'],
            dueDate: _parseDate(taskMap['due_date']),
            priority: _parsePriority(taskMap['priority']),
            category: taskMap['category'],
          );
          addedTasks.add(task.title);
        }

        final allTasks = await _db.getAllTasks(completed: false);
        return ActionResult.success(
          'Am adăugat ${addedTasks.length} task-uri: ${addedTasks.join(", ")}.',
          data: {
            'count': addedTasks.length,
            'tasks': addedTasks,
            'total_tasks': allTasks.length,
          },
        );
      }

      // Single task
      final task = await _db.createTask(
        title: data['title'] ?? 'Task fără titlu',
        description: data['description'],
        dueDate: _parseDate(data['due_date']),
        priority: _parsePriority(data['priority']),
        category: data['category'],
      );

      final allTasks = await _db.getAllTasks(completed: false);
      return ActionResult.success(
        'Task-ul "${task.title}" a fost adăugat.',
        data: {
          'task_id': task.id,
          'task_title': task.title,
          'total_tasks': allTasks.length,
        },
      );
    } catch (e) {
      return ActionResult.error('Eroare la adăugarea task-ului: $e');
    }
  }

  Future<ActionResult> _listTasks(Map<String, dynamic> data) async {
    try {
      final tasks = await _db.getAllTasks(
        completed: data['completed'] as bool?,
        category: data['category'] as String?,
      );

      final taskList = tasks
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'description': t.description,
              'due_date': t.dueDate?.toIso8601String(),
              'priority': t.priority,
              'category': t.category,
              'is_completed': t.isCompleted,
            },
          )
          .toList();

      return ActionResult.success(
        tasks.isEmpty
            ? 'Nu ai niciun task activ.'
            : 'Ai ${tasks.length} task-uri.',
        data: {'count': tasks.length, 'tasks': taskList},
      );
    } catch (e) {
      return ActionResult.error('Eroare la listarea task-urilor: $e');
    }
  }

  Future<ActionResult> _completeTask(Map<String, dynamic> data) async {
    try {
      Task? task;

      if (data['task_id'] != null) {
        task = await _db.getTask(data['task_id'].toString());
      } else if (data['task_title'] != null) {
        task = await _db.findTaskByTitle(data['task_title']);
      }

      if (task == null || task.id.isEmpty) {
        return ActionResult.error('Task-ul nu a fost găsit.');
      }

      await _db.completeTask(task.id);
      return ActionResult.success(
        'Task-ul "${task.title}" a fost marcat ca finalizat.',
      );
    } catch (e) {
      return ActionResult.error('Eroare la finalizarea task-ului: $e');
    }
  }

  Future<ActionResult> _deleteTask(Map<String, dynamic> data) async {
    try {
      Task? task;

      if (data['task_id'] != null) {
        task = await _db.getTask(data['task_id'].toString());
      } else if (data['task_title'] != null) {
        task = await _db.findTaskByTitle(data['task_title']);
      }

      if (task == null || task.id.isEmpty) {
        return ActionResult.error('Task-ul nu a fost găsit.');
      }

      await _db.deleteTask(task.id);
      return ActionResult.success('Task-ul "${task.title}" a fost șters.');
    } catch (e) {
      return ActionResult.error('Eroare la ștergerea task-ului: $e');
    }
  }

  // ============ SHOPPING ACTIONS ============

  Future<ActionResult> _addShoppingItem(Map<String, dynamic> data) async {
    try {
      // Check if data contains an 'items' list (multiple items)
      if (data.containsKey('items') && data['items'] is List) {
        final itemsList = data['items'] as List;
        final addedItems = <String>[];
        for (final itemData in itemsList) {
          final itemMap = itemData as Map<String, dynamic>;
          final item = await _db.createShoppingItem(
            name: itemMap['name'] ?? 'Produs',
            quantity: itemMap['quantity'] ?? '1',
            category: itemMap['category'],
            notes: itemMap['notes'],
            priceEstimate: itemMap['price_estimate']?.toDouble(),
          );
          addedItems.add(item.name);
        }

        final allItems = await _db.getAllShoppingItems(purchased: false);

        List<String> storeSuggestions = _suggestStoresForShopping(addedItems);
        String suggestionText = storeSuggestions.isNotEmpty
            ? ' Îți recomand să verifici: ${storeSuggestions.join(', ')}.'
            : '';
        Map<String, dynamic>? liveComparisonData;

        // For larger lists, compare live prices and recommend the best store this week.
        if (addedItems.length >= 6) {
          final liveComparison = await _search.compareShoppingListPrices(
            addedItems,
          );

          if (liveComparison.success &&
              liveComparison.recommendedStore != null &&
              liveComparison.recommendedStore!.isNotEmpty) {
            final topStore = liveComparison.recommendedStore!;
            final topSummary = liveComparison.storeSummaries.firstWhere(
              (s) => s.store == topStore,
              orElse: () => liveComparison.storeSummaries.first,
            );

            final firstDealItems = liveComparison.matchedPrices
                .where((m) => m.store == topStore)
                .map((m) => m.item)
                .toSet()
                .take(3)
                .toList();

            suggestionText =
                ' Recomandare live: săptămâna aceasta ieși mai bine la $topStore (estimare coș: ${topSummary.estimatedTotal.toStringAsFixed(2)} lei pentru ${topSummary.matchedItems}/${liveComparison.scannedItems.length} produse analizate).${firstDealItems.isNotEmpty ? ' Produse avantajoase: ${firstDealItems.join(', ')}.' : ''}';

            storeSuggestions = [topStore];
            liveComparisonData = liveComparison.toJson();
          }
        }

        return ActionResult.success(
          'Am adăugat ${addedItems.length} produse: ${addedItems.join(", ")}.${suggestionText}',
          data: {
            'count': addedItems.length,
            'items': addedItems,
            'total_items': allItems.length,
            'store_suggestions': storeSuggestions,
            if (liveComparisonData != null)
              'live_price_comparison': liveComparisonData,
          },
        );
      }

      // Single item
      final item = await _db.createShoppingItem(
        name: data['name'] ?? 'Produs',
        quantity: data['quantity'] ?? '1',
        category: data['category'],
        notes: data['notes'],
        priceEstimate: data['price_estimate']?.toDouble(),
      );

      final allItems = await _db.getAllShoppingItems(purchased: false);
      return ActionResult.success(
        'Am adăugat "${item.name}" pe lista de cumpărături.',
        data: {
          'item_id': item.id,
          'item_name': item.name,
          'total_items': allItems.length,
        },
      );
    } catch (e) {
      return ActionResult.error('Eroare la adăugarea produsului: $e');
    }
  }

  Future<ActionResult> _listShopping(Map<String, dynamic> data) async {
    try {
      final items = await _db.getAllShoppingItems(
        purchased: data['purchased'] as bool?,
      );

      final itemList = items
          .map(
            (i) => {
              'id': i.id,
              'name': i.name,
              'quantity': i.quantity,
              'category': i.category,
              'is_purchased': i.isPurchased,
              'price_estimate': i.priceEstimate,
            },
          )
          .toList();

      final total = await _db.getShoppingListTotal();

      return ActionResult.success(
        items.isEmpty
            ? 'Lista ta de cumpărături este goală.'
            : 'Ai ${items.length} produse pe listă.',
        data: {
          'count': items.length,
          'items': itemList,
          'total_estimate': total,
        },
      );
    } catch (e) {
      return ActionResult.error('Eroare la listarea cumpărăturilor: $e');
    }
  }

  Future<ActionResult> _removeShoppingItem(Map<String, dynamic> data) async {
    try {
      ShoppingItem? item;

      if (data['item_id'] != null) {
        item = await _db.getShoppingItem(data['item_id'].toString());
      } else if (data['item_name'] != null) {
        item = await _db.findShoppingItemByName(data['item_name']);
      }

      if (item == null) {
        return ActionResult.error('Produsul nu a fost găsit pe listă.');
      }

      await _db.deleteShoppingItem(item.id);
      return ActionResult.success(
        '"${item.name}" a fost șters de pe lista de cumpărături.',
      );
    } catch (e) {
      return ActionResult.error('Eroare la ștergerea produsului: $e');
    }
  }

  // ============ EMAIL ACTIONS ============

  Future<ActionResult> _sendEmail(Map<String, dynamic> data) async {
    try {
      final to = data['to'] as String?;
      final subject = data['subject'] as String?;
      final body = data['body'] as String?;

      if (to == null || to.isEmpty) {
        return ActionResult.error('Adresa de email lipsește.');
      }
      if (subject == null || subject.isEmpty) {
        return ActionResult.error('Subiectul emailului lipsește.');
      }
      if (body == null || body.isEmpty) {
        return ActionResult.error('Conținutul emailului lipsește.');
      }

      final result = await _email.sendEmail(
        to: to,
        subject: subject,
        body: body,
      );

      if (result.success) {
        // Log the action
        await _db.logAction(
          actionType: 'email',
          target: to,
          content: 'Subject: $subject\n\n$body',
        );
        return ActionResult.success('Email-ul a fost trimis către $to.');
      } else {
        return ActionResult.error(
          result.error ?? 'Eroare la trimiterea emailului.',
        );
      }
    } catch (e) {
      return ActionResult.error('Eroare la trimiterea emailului: $e');
    }
  }

  Future<ActionResult> _readEmails(Map<String, dynamic> data) async {
    final result = await _email.getRecentEmails(count: data['count'] ?? 5);

    if (result.success && result.emails != null) {
      return ActionResult.success(
        'Ai ${result.emails!.length} emailuri recente.',
        data: {
          'count': result.emails!.length,
          'emails': result.emails!.map((e) => e.toJson()).toList(),
        },
      );
    } else {
      return ActionResult.error(
        result.error ?? 'Eroare la citirea emailurilor.',
      );
    }
  }

  Future<ActionResult> _readLastEmail(Map<String, dynamic> data) async {
    final result = await _email.getLastEmail();

    if (result.success && result.email != null) {
      return ActionResult.success(
        'Ultimul email de la ${result.email!.from}.',
        data: {'email': result.email!.toJson()},
      );
    } else {
      return ActionResult.error(result.error ?? 'Eroare la citirea emailului.');
    }
  }

  Future<ActionResult> _searchEmails(Map<String, dynamic> data) async {
    final query = data['query'] as String?;
    if (query == null || query.isEmpty) {
      return ActionResult.error('Termenul de căutare lipsește.');
    }

    final result = await _email.searchEmails(query);

    if (result.success && result.emails != null) {
      return ActionResult.success(
        'Am găsit ${result.emails!.length} emailuri.',
        data: {
          'count': result.emails!.length,
          'emails': result.emails!.map((e) => e.toJson()).toList(),
        },
      );
    } else {
      return ActionResult.error(
        result.error ?? 'Eroare la căutarea emailurilor.',
      );
    }
  }

  // ============ SEARCH ACTIONS ============

  Future<ActionResult> _searchInternet(Map<String, dynamic> data) async {
    try {
      final query = data['query'] as String?;
      if (query == null || query.isEmpty) {
        return ActionResult.error('Termenul de căutare lipsește.');
      }

      final result = await _search.search(query);

      if (result.success) {
        return ActionResult.success(
          'Am găsit informații despre "$query".',
          data: {
            'query': query,
            'direct_answer': result.directAnswer,
            'results': result.results
                .map(
                  (r) => {
                    'title': r.title,
                    'snippet': r.snippet,
                    'link': r.link,
                  },
                )
                .toList(),
            'formatted': result.formatForAI(),
          },
        );
      } else {
        return ActionResult.error(result.error ?? 'Eroare la căutare.');
      }
    } catch (e) {
      return ActionResult.error('Eroare la căutarea pe internet: $e');
    }
  }

  Future<ActionResult> _compareShoppingPrices(Map<String, dynamic> data) async {
    try {
      final dynamic rawItems = data['items'];
      final List<String> items = rawItems is List
          ? rawItems.map((e) => e.toString()).toList()
          : [];

      final List<String> normalizedItems = items
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (normalizedItems.isEmpty) {
        final current = await _db.getAllShoppingItems(purchased: false);
        normalizedItems.addAll(current.map((e) => e.name));
      }

      if (normalizedItems.isEmpty) {
        return ActionResult.error(
          'Nu ai produse în lista de cumpărături pentru comparație.',
        );
      }

      final comparison = await _search.compareShoppingListPrices(
        normalizedItems,
      );
      if (!comparison.success || comparison.recommendedStore == null) {
        return ActionResult.error(
          comparison.error ??
              'Nu am găsit suficiente date live pentru comparație.',
        );
      }

      final topStore = comparison.recommendedStore!;
      final topSummary = comparison.storeSummaries.firstWhere(
        (s) => s.store == topStore,
        orElse: () => comparison.storeSummaries.first,
      );

      final dealItems = comparison.matchedPrices
          .where((m) => m.store == topStore)
          .map((m) => m.item)
          .toSet()
          .take(4)
          .toList();

      return ActionResult.success(
        'Pe baza prețurilor live, cel mai avantajos magazin acum este $topStore (estimare: ${topSummary.estimatedTotal.toStringAsFixed(2)} lei).${dealItems.isNotEmpty ? ' Produse cu preț bun: ${dealItems.join(', ')}.' : ''}',
        data: comparison.toJson(),
      );
    } catch (e) {
      return ActionResult.error('Eroare la compararea prețurilor: $e');
    }
  }

  // ============ CALENDAR ACTIONS ============

  Future<ActionResult> _scheduleMeeting(Map<String, dynamic> data) async {
    try {
      final title = data['title'] as String?;
      final date = data['date'] as String?;
      final time = data['time'] as String?;
      final attendeeEmail = data['attendee_email'] as String?;
      final attendeeName = data['attendee_name'] as String?;
      final description = data['description'] as String?;
      final durationMinutes = data['duration_minutes'] ?? 60;

      if (title == null || title.isEmpty) {
        return ActionResult.error('Titlul întâlnirii lipsește.');
      }
      if (date == null || time == null) {
        return ActionResult.error('Data și ora întâlnirii lipsesc.');
      }

      // Parse date and time
      final startTime = _parseDateTime(date, time);
      if (startTime == null) {
        return ActionResult.error('Format invalid pentru dată sau oră.');
      }

      final endTime = startTime.add(Duration(minutes: durationMinutes as int));

      // Generate a simple Meet link (in production, use Google Calendar API)
      final meetId = DateTime.now().millisecondsSinceEpoch.toString();
      final meetLink = 'https://meet.google.com/$meetId';

      // Create calendar event
      final event = await _db.createCalendarEvent(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        meetLink: meetLink,
        attendeeEmail: attendeeEmail,
        attendeeName: attendeeName,
        reminderTime: startTime.subtract(const Duration(hours: 1)),
      );

      // Send invitation email if attendee is specified
      if (attendeeEmail != null && attendeeEmail.isNotEmpty) {
        await _email.sendMeetingInvitation(
          to: attendeeEmail,
          attendeeName: attendeeName ?? 'Participant',
          meetingTitle: title,
          startTime: startTime,
          meetLink: meetLink,
          description: description,
        );

        await _db.logAction(
          actionType: 'meeting_invitation',
          target: attendeeEmail,
          content: 'Invited to: $title at $date $time',
        );
      }

      // Send confirmation email to self
      final selfEmail = _email.userEmail;
      if (selfEmail != null && selfEmail.isNotEmpty) {
        try {
          await _email.sendMeetingInvitation(
            to: selfEmail,
            attendeeName: 'Tu',
            meetingTitle: title,
            startTime: startTime,
            meetLink: meetLink,
            description:
                'Confirmare întâlnire: ${description ?? title}\n\nParticipant: ${attendeeName ?? attendeeEmail ?? "N/A"}',
          );
          print('📧 Email de confirmare trimis la: $selfEmail');
        } catch (e) {
          print('⚠️ Nu s-a putut trimite email-ul de confirmare: $e');
        }
      }

      // Schedule local notifications (30 min before and at meeting time)
      try {
        await _notification.scheduleMeetingReminder(
          id: event.id.hashCode,
          title: title,
          meetLink: meetLink,
          meetingTime: startTime,
        );
        await _notification.scheduleMeetingStartNotification(
          id: event.id.hashCode + 1,
          title: title,
          meetLink: meetLink,
          meetingTime: startTime,
        );
        print('🔔 Notificări programate pentru întâlnire');
      } catch (e) {
        print('⚠️ Nu s-au putut programa notificările: $e');
      }

      // Add event to device's native calendar with 30-min reminder
      try {
        final calendarEventId = await _deviceCalendar.addMeetingToCalendar(
          title: title,
          startTime: startTime,
          endTime: endTime,
          description: description,
          meetLink: meetLink,
          attendeeEmail: attendeeEmail,
          attendeeName: attendeeName,
          reminderMinutesBefore: 30,
        );
        if (calendarEventId != null) {
          print('📅 Eveniment adăugat automat în calendar: $calendarEventId');
        } else {
          print('⚠️ Nu s-a putut adăuga în calendar (verifică permisiunile)');
        }
      } catch (e) {
        print('⚠️ Eroare la adăugarea în calendar: $e');
      }

      final formattedDate = DateFormat('d MMMM yyyy', 'ro').format(startTime);
      final formattedTime = DateFormat('HH:mm').format(startTime);

      return ActionResult.success(
        'Întâlnirea "$title" a fost programată pentru $formattedDate la ora $formattedTime.${attendeeEmail != null ? " Invitație trimisă către $attendeeEmail." : ""}',
        data: {
          'event_id': event.id,
          'title': title,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'meet_link': meetLink,
          'attendee_email': attendeeEmail,
        },
      );
    } catch (e) {
      return ActionResult.error('Eroare la programarea întâlnirii: $e');
    }
  }

  Future<ActionResult> _addCalendarEvent(Map<String, dynamic> data) async {
    try {
      final title = data['title'] as String?;
      final date = data['date'] as String?;
      final time = data['time'] as String?;
      final description = data['description'] as String?;
      final durationMinutes = data['duration_minutes'] ?? 60;

      if (title == null || title.isEmpty) {
        return ActionResult.error('Titlul evenimentului lipsește.');
      }
      if (date == null || time == null) {
        return ActionResult.error('Data și ora evenimentului lipsesc.');
      }

      final startTime = _parseDateTime(date, time);
      if (startTime == null) {
        return ActionResult.error('Format invalid pentru dată sau oră.');
      }

      final endTime = startTime.add(Duration(minutes: durationMinutes as int));

      final event = await _db.createCalendarEvent(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
      );

      final formattedDate = DateFormat('d MMMM yyyy', 'ro').format(startTime);
      final formattedTime = DateFormat('HH:mm').format(startTime);

      return ActionResult.success(
        'Evenimentul "$title" a fost adăugat în calendar pentru $formattedDate la ora $formattedTime.',
        data: {
          'event_id': event.id,
          'title': title,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
        },
      );
    } catch (e) {
      return ActionResult.error('Eroare la adăugarea evenimentului: $e');
    }
  }

  Future<ActionResult> _listCalendarEvents(Map<String, dynamic> data) async {
    try {
      final events = await _db.getUpcomingEvents(days: 7);

      final eventList = events
          .map(
            (e) => {
              'id': e.id,
              'title': e.title,
              'start_time': e.startTime.toIso8601String(),
              'end_time': e.endTime.toIso8601String(),
              'meet_link': e.meetLink,
              'attendee': e.attendeeName ?? e.attendeeEmail,
              'status': e.status,
            },
          )
          .toList();

      return ActionResult.success(
        events.isEmpty
            ? 'Nu ai evenimente programate săptămâna aceasta.'
            : 'Ai ${events.length} evenimente programate.',
        data: {'count': events.length, 'events': eventList},
      );
    } catch (e) {
      return ActionResult.error('Eroare la listarea evenimentelor: $e');
    }
  }

  Future<ActionResult> _cancelCalendarEvent(Map<String, dynamic> data) async {
    try {
      final eventId = data['event_id']?.toString();
      final title = data['title'] as String?;

      CalendarEvent? event;

      if (eventId != null) {
        event = await _db.getCalendarEvent(eventId);
      } else if (title != null) {
        final events = await _db.getAllCalendarEvents(status: 'scheduled');
        event = events.firstWhere(
          (e) => e.title.toLowerCase().contains(title.toLowerCase()),
          orElse: () => CalendarEvent(
            id: '',
            title: '',
            startTime: DateTime.now(),
            endTime: DateTime.now(),
          ),
        );
      }

      if (event == null || event.id.isEmpty) {
        return ActionResult.error('Evenimentul nu a fost găsit.');
      }

      await _db.cancelCalendarEvent(event.id);

      // Send cancellation email if there was an attendee
      if (event.attendeeEmail != null && event.attendeeEmail!.isNotEmpty) {
        await _email.sendEmail(
          to: event.attendeeEmail!,
          subject: 'Anulare: ${event.title}',
          body:
              'Întâlnirea "${event.title}" programată pentru ${DateFormat('d MMMM yyyy').format(event.startTime)} a fost anulată.\n\nNe cerem scuze pentru inconvenient.',
        );
      }

      return ActionResult.success(
        'Evenimentul "${event.title}" a fost anulat.',
      );
    } catch (e) {
      return ActionResult.error('Eroare la anularea evenimentului: $e');
    }
  }

  // ============ HELPER METHODS ============

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;

    try {
      // Try ISO format
      return DateTime.parse(dateStr);
    } catch (_) {
      // Try common formats
      final now = DateTime.now();
      final lower = dateStr.toLowerCase();

      if (lower == 'mâine' || lower == 'maine') {
        return DateTime(now.year, now.month, now.day + 1);
      }
      if (lower == 'poimâine' || lower == 'poimaine') {
        return DateTime(now.year, now.month, now.day + 2);
      }
      if (lower == 'azi' || lower == 'astăzi' || lower == 'astazi') {
        return DateTime(now.year, now.month, now.day);
      }

      return null;
    }
  }

  DateTime? _parseDateTime(String date, String time) {
    try {
      final parsedDate = _parseDate(date);
      if (parsedDate == null) return null;

      final timeParts = time.split(':');
      if (timeParts.length >= 2) {
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        return DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
          hour,
          minute,
        );
      }

      return parsedDate;
    } catch (_) {
      return null;
    }
  }

  int _parsePriority(dynamic priority) {
    if (priority == null) return 2;
    if (priority is int) return priority.clamp(1, 3);
    if (priority is String) {
      switch (priority.toLowerCase()) {
        case 'low':
        case 'scăzută':
        case 'scazuta':
          return 1;
        case 'high':
        case 'ridicată':
        case 'ridicata':
        case 'mare':
          return 3;
        default:
          return 2;
      }
    }
    return 2;
  }

  List<String> _suggestStoresForShopping(List<String> itemNames) {
    if (itemNames.isEmpty) return const [];

    final normalized = itemNames.map((e) => e.toLowerCase()).toList();

    final hasFreshProduce = normalized.any(
      (name) =>
          name.contains('legume') ||
          name.contains('fructe') ||
          name.contains('salata') ||
          name.contains('rosii') ||
          name.contains('castraveti') ||
          name.contains('mere') ||
          name.contains('banane'),
    );

    final hasHousehold = normalized.any(
      (name) =>
          name.contains('detergent') ||
          name.contains('hartie') ||
          name.contains('burete') ||
          name.contains('sapun') ||
          name.contains('sampon'),
    );

    if (itemNames.length >= 10) {
      return const [
        'Kaufland (coș mare, promoții multe)',
        'Carrefour (varietate mare de produse)',
        'Auchan (bun pentru cumpărături în volum)',
      ];
    }

    if (hasFreshProduce) {
      return const [
        'Lidl (preț bun la legume/fructe)',
        'Piața locală (produse proaspete)',
      ];
    }

    if (hasHousehold) {
      return const [
        'Carrefour (raion casă/curățenie)',
        'Auchan (gamă largă non-food)',
      ];
    }

    return const ['Lidl', 'Kaufland', 'Carrefour'];
  }
}
