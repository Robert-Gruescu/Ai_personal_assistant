import 'package:flutter/material.dart';
import '../core/services/database_service.dart';
import '../core/models/models.dart';

/// Panouri (bottom sheets) partajate între ecranul de chat și cel de voce:
/// lista de task-uri și lista de cumpărături. Astfel codul nu e duplicat.

// ─────────────────────────────────────────────────────────────────────────────
// Tasks Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class TasksSheet extends StatefulWidget {
  final DatabaseService db;
  final VoidCallback? onChanged;
  const TasksSheet({super.key, required this.db, this.onChanged});

  @override
  State<TasksSheet> createState() => _TasksSheetState();
}

class _TasksSheetState extends State<TasksSheet> {
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await widget.db.getAllTasks(completed: false);
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    }
  }

  Future<void> _complete(Task task) async {
    await widget.db.completeTask(task.id);
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
    widget.onChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ "${task.title}" marcat ca finalizat')),
      );
    }
  }

  Future<void> _delete(Task task) async {
    await widget.db.deleteTask(task.id);
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Colors.indigo, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Task-uri active',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_tasks.length} task${_tasks.length != 1 ? "-uri" : ""}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.task_alt, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Nu ai task-uri active!',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _tasks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final task = _tasks[i];
                  final priorityColor = task.priority == 3
                      ? Colors.red
                      : task.priority == 2
                      ? Colors.orange
                      : Colors.green;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    leading: GestureDetector(
                      onTap: () => _complete(task),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.indigo, width: 2),
                        ),
                        child: const Icon(Icons.check, size: 16, color: Colors.indigo),
                      ),
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: task.dueDate != null
                        ? Text(
                            '📅 ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : task.category != null
                        ? Text(task.category!, style: const TextStyle(fontSize: 12))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: priorityColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          onPressed: () => _delete(task),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shopping Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class ShoppingSheet extends StatefulWidget {
  final DatabaseService db;
  final VoidCallback? onChanged;
  const ShoppingSheet({super.key, required this.db, this.onChanged});

  @override
  State<ShoppingSheet> createState() => _ShoppingSheetState();
}

class _ShoppingSheetState extends State<ShoppingSheet> {
  List<ShoppingItem> _items = [];
  bool _loading = true;
  bool _showPurchased = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getAllShoppingItems(
      purchased: _showPurchased ? null : false,
    );
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _markPurchased(ShoppingItem item) async {
    await widget.db.markShoppingItemPurchased(item.id);
    setState(() {
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) _items[idx] = item.copyWith(isPurchased: true);
    });
    widget.onChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🛒 "${item.name}" marcat ca cumpărat')),
      );
    }
  }

  Future<void> _delete(ShoppingItem item) async {
    await widget.db.deleteShoppingItem(item.id);
    setState(() => _items.removeWhere((i) => i.id == item.id));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final unpurchased = _items.where((i) => !i.isPurchased).toList();
    final purchased = _items.where((i) => i.isPurchased).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.teal,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Lista de cumpărături',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showPurchased = !_showPurchased;
                    _loading = true;
                  });
                  _load();
                },
                child: Text(
                  _showPurchased ? 'Ascunde cumpărate' : 'Arată toate',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${unpurchased.length} de cumpărat',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Lista de cumpărături este goală!',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...unpurchased.map(
                    (item) => ShoppingTile(
                      item: item,
                      onCheck: () => _markPurchased(item),
                      onDelete: () => _delete(item),
                    ),
                  ),
                  if (_showPurchased && purchased.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '✅ Deja cumpărate',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...purchased.map(
                      (item) => ShoppingTile(
                        item: item,
                        purchased: true,
                        onCheck: null,
                        onDelete: () => _delete(item),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Single shopping tile ──────────────────────────────────────────────────────

class ShoppingTile extends StatelessWidget {
  final ShoppingItem item;
  final bool purchased;
  final VoidCallback? onCheck;
  final VoidCallback onDelete;

  const ShoppingTile({
    super.key,
    required this.item,
    this.purchased = false,
    required this.onCheck,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: GestureDetector(
        onTap: onCheck,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: purchased ? Colors.teal : Colors.transparent,
            border: Border.all(color: Colors.teal, width: 2),
          ),
          child: purchased
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
      title: Text(
        item.name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          decoration: purchased ? TextDecoration.lineThrough : null,
          color: purchased ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        'Cantitate: ${item.quantity}'
        '${item.category != null ? "  •  ${item.category}" : ""}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.priceEstimate != null)
            Text(
              '${item.priceEstimate!.toStringAsFixed(0)} lei',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
