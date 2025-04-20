import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:path_provider/path_provider.dart';
import '../database_helper.dart';
import '../purchase.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';

import 'package:receipt_scanner/theme/app_colors.dart';

import 'dart:io';

import '../api/veryfi_api.dart';
final _veryfi = VeryfiApi();
enum SortOption {
  dateNewest,
  dateOldest,
}

enum TimeFilter {
  allTime,
  thisYear,
  last6Months,
  last3Months,
  thisMonth,
  thisWeek,
}

enum ExpenseCategory {
  groceries,
  dining,
  transportation,
  healthcare,
  clothing,
  electronics,
  homeMaintenance,
  onlineShopping,
  travel,
  entertainment,
  generalMerchandise,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dbHelper = DatabaseHelper.instance;
  List<ExpenseEntry> _expenses = [];
  final TextEditingController _searchController = TextEditingController();
  double _totalSpent = 0.0;
  SortOption _currentSort = SortOption.dateNewest;
  String _searchQuery = '';
  TimeFilter _currentTimeFilter = TimeFilter.allTime;
  ExpenseCategory? _selectedFilterCategory;
  ExpenseCategory _selectedCategory = ExpenseCategory.generalMerchandise;
  int? _expandedIndex;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      // Ensure database is initialized
      await _dbHelper.database;

      // Check if database schema is correct
      final isSchemaValid = await _dbHelper.checkDatabaseSchema();
      if (!isSchemaValid) {
        // Reset database if schema is invalid
        await _dbHelper.resetDatabase();
      }

      await _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing database: $e')),
        );
      }
    }
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    try {
      final purchases = await _dbHelper.getAllPurchases();
      setState(() {
        _expenses = purchases.map((p) =>
            ExpenseEntry(
              name: p['name'],
              amount: p['price'],
              date: DateTime.parse(p['date']),
              category: ExpenseCategory.values.firstWhere(
                    (e) =>
                e
                    .toString()
                    .split('.')
                    .last == p['category'].toLowerCase(),
                orElse: () => ExpenseCategory.generalMerchandise,
              ),
              imagePath: p['imagePath'],
            )).toList();
        _calculateTotalSpent();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading expenses: $e')),
      );
    }
  }

  void _calculateTotalSpent() {
    _totalSpent = _expenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  double get _filteredTotalSpent {
    final now = DateTime.now();
    final filteredExpenses = _expenses.where((expense) {
      switch (_currentTimeFilter) {
        case TimeFilter.allTime:
          return true;
        case TimeFilter.thisYear:
          return expense.date.year == now.year;
        case TimeFilter.last6Months:
          final sixMonthsAgo = DateTime(now.year, now.month - 6, now.day);
          return expense.date.isAfter(sixMonthsAgo);
        case TimeFilter.last3Months:
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return expense.date.isAfter(threeMonthsAgo);
        case TimeFilter.thisMonth:
          return expense.date.year == now.year &&
              expense.date.month == now.month;
        case TimeFilter.thisWeek:
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          return expense.date.isAfter(startOfWeek);
      }
    });
    return filteredExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  String get _timeFilterLabel {
    switch (_currentTimeFilter) {
      case TimeFilter.allTime:
        return 'All Time';
      case TimeFilter.thisYear:
        return 'This Year';
      case TimeFilter.last6Months:
        return 'Last 6 Months';
      case TimeFilter.last3Months:
        return 'Last 3 Months';
      case TimeFilter.thisMonth:
        return 'This Month';
      case TimeFilter.thisWeek:
        return 'This Week';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExpenseEntry> get _filteredExpenses {
    final now = DateTime.now();
    var filtered = _expenses.where((expense) {
      // Apply time filter
      switch (_currentTimeFilter) {
        case TimeFilter.allTime:
          return true;
        case TimeFilter.thisYear:
          return expense.date.year == now.year;
        case TimeFilter.last6Months:
          final sixMonthsAgo = DateTime(now.year, now.month - 6, now.day);
          return expense.date.isAfter(sixMonthsAgo);
        case TimeFilter.last3Months:
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return expense.date.isAfter(threeMonthsAgo);
        case TimeFilter.thisMonth:
          return expense.date.year == now.year &&
              expense.date.month == now.month;
        case TimeFilter.thisWeek:
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          return expense.date.isAfter(startOfWeek);
      }
    }).toList();

    // Apply category filter if selected
    if (_selectedFilterCategory != null) {
      filtered = filtered.where((expense) => 
        expense.category == _selectedFilterCategory
      ).toList();
    }

    // Apply search filter if there's a search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((expense) =>
          expense.name.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    return filtered;
  }

  Map<DateTime, List<ExpenseEntry>> get _groupedExpenses {
    final grouped = <DateTime, List<ExpenseEntry>>{};
    
    for (final expense in _filteredExpenses) {
      final date = DateTime(
        expense.date.year,
        expense.date.month,
        expense.date.day,
      );
      grouped.putIfAbsent(date, () => []).add(expense);
    }

    // Sort expenses within each date group
    for (final expenses in grouped.values) {
      expenses.sort((a, b) => a.name.compareTo(b.name));
    }

    return Map.fromEntries(
      grouped.entries.toList()
        ..sort((a, b) =>
          _currentSort == SortOption.dateNewest
              ? b.key.compareTo(a.key)
              : a.key.compareTo(b.key))
    );
  }

  void _addExpense() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          AddExpenseSheet(
            onAdd: (expense) async {
              try {
                final purchase = Purchase(
                  name: _capitalizeWords(expense.name),
                  date: expense.date.toString(),
                  price: expense.amount,
                  category: expense.category
                      .toString()
                      .split('.')
                      .last,
                );
                await _dbHelper.createPurchase(purchase.toMap());
                await _loadExpenses();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error adding expense: $e')),
                );
              }
            },
          ),
    );
  }

  void _removeExpense(int index) async {
    try {
      final expense = _expenses[index];
      final purchases = await _dbHelper.getAllPurchases();
      final matchingPurchase = purchases.firstWhere(
            (p) =>
        p['name'] == expense.name &&
            p['price'] == expense.amount &&
            p['date'] == expense.date.toString(),
      );
      await _dbHelper.deletePurchase(matchingPurchase['id']);
      await _loadExpenses();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing expense: $e')),
      );
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Sort by'),
            tileColor: Theme.of(context).primaryColor.withOpacity(0.1),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Date (Newest)'),
            selected: _currentSort == SortOption.dateNewest,
            onTap: () {
              setState(() {
                _currentSort = SortOption.dateNewest;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Date (Oldest)'),
            selected: _currentSort == SortOption.dateOldest,
            onTap: () {
              setState(() {
                _currentSort = SortOption.dateOldest;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.groceries:
        return 'Groceries';
      case ExpenseCategory.dining:
        return 'Dining';
      case ExpenseCategory.transportation:
        return 'Transportation';
      case ExpenseCategory.healthcare:
        return 'Healthcare';
      case ExpenseCategory.clothing:
        return 'Clothing';
      case ExpenseCategory.electronics:
        return 'Electronics';
      case ExpenseCategory.homeMaintenance:
        return 'Home Maintenance';
      case ExpenseCategory.onlineShopping:
        return 'Online Shopping';
      case ExpenseCategory.travel:
        return 'Travel';
      case ExpenseCategory.entertainment:
        return 'Entertainment';
      case ExpenseCategory.generalMerchandise:
        return 'General Merchandise';
    }
  }

  Color _getCategoryColor(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.groceries:
        return Colors.green;
      case ExpenseCategory.dining:
        return Colors.orange;
      case ExpenseCategory.transportation:
        return Colors.blue;
      case ExpenseCategory.healthcare:
        return Colors.red;
      case ExpenseCategory.clothing:
        return Colors.purple;
      case ExpenseCategory.electronics:
        return Colors.indigo;
      case ExpenseCategory.homeMaintenance:
        return Colors.brown;
      case ExpenseCategory.onlineShopping:
        return Colors.teal;
      case ExpenseCategory.travel:
        return Colors.amber;
      case ExpenseCategory.entertainment:
        return Colors.pink;
      case ExpenseCategory.generalMerchandise:
        return Colors.grey;
    }
  }

  Future<String?> _takePicture() async {
    // Show prompt dialog first
    final bool? shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Take Receipt Photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt,
                  size: 48,
                  color: Colors.black,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Make sure to:\n'
                      '• Place the receipt on a flat surface\n'
                      '• Ensure good lighting\n'
                      '• Keep the receipt within the frame\n'
                      '• Hold the camera steady',
                  textAlign: TextAlign.left,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Camera'),
              ),
            ],
          ),
    );

    if (shouldProceed != true) return null;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 600,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (image != null) {
      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'receipt_${DateTime
          .now()
          .millisecondsSinceEpoch}.jpg';
      final String filePath = '${directory.path}/$fileName';

      // Copy the image to the app's documents directory
      final savedFile = await File(image.path).copy(filePath);

      // Verify the file exists and is accessible
      if (await savedFile.exists()) {
        return filePath;
      }
    }
    return null;
  }

  void _showReceiptImage(String imagePath) {
    showDialog(
      context: context,
      builder: (context) =>
          Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Receipt Image',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<File>(
                  future: Future.value(File(imagePath)),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.existsSync()) {
                      return Image.file(
                        snapshot.data!,
                        fit: BoxFit.contain,
                      );
                    } else {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Image not found'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.accent, // COLORS: Main background color
      appBar: AppBar(
        backgroundColor: AppColors.roseGold,  // COLORS: top app bar color
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'stats':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StatsScreen(),
                    ),
                  );
                  break;
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'stats',
                child: ListTile(
                  leading: Icon(Icons.bar_chart),
                  title: Text('Statistics'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Card(
                  color: AppColors.background,  // COLORS: total spent card color
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Spent',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            DropdownButton<TimeFilter>(
                              value: _currentTimeFilter,
                              items: TimeFilter.values.map((filter) {
                                return DropdownMenuItem(
                                  value: filter,
                                  child: Text(_getTimeFilterLabel(filter)),
                                );
                              }).toList(),
                              onChanged: (TimeFilter? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _currentTimeFilter = newValue;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '\$${_filteredTotalSpent.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search expenses...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            filled: true,
                            fillColor: AppColors.secondary,
                            isDense: true,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.secondary,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ExpenseCategory?>(
                            value: _selectedFilterCategory,
                            isExpanded: true,
                            hint: const Text('Filter by category'),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Categories'),
                              ),
                              ...ExpenseCategory.values.map((category) {
                                return DropdownMenuItem(
                                  value: category,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 12,
                                        color: _getCategoryColor(category),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_getCategoryLabel(category)),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                            onChanged: (ExpenseCategory? newValue) {
                              setState(() {
                                _selectedFilterCategory = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final dates = _groupedExpenses.keys.toList();
                final date = dates[index];
                final expenses = _groupedExpenses[date]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        DateFormat('MMMM dd, yyyy').format(date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    ...expenses.map((expense) {
                      final originalIndex = _expenses.indexOf(expense);
                      final category = expense.category ??
                          ExpenseCategory.generalMerchandise;
                      final isExpanded = _expandedIndex == originalIndex;

                      return Dismissible(
                        key: Key(expense.hashCode.toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog(
                            context: context,
                            builder: (context) =>
                                AlertDialog(
                                  title: const Text('Delete Expense'),
                                  content: Text(
                                    'Are you sure you want to delete "${expense
                                        .name}"?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                          );
                        },
                        onDismissed: (direction) {
                          _removeExpense(originalIndex);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${expense.name} deleted'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () {
                                  setState(() {
                                    _expenses.insert(originalIndex, expense);
                                    _calculateTotalSpent();
                                  });
                                },
                              ),
                            ),
                          );
                        },
                        child: Card(
                          color: AppColors.background,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ExpansionTile(
                            title: Text(expense.name),
                            subtitle: Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getCategoryColor(category)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getCategoryLabel(category),
                                      style: TextStyle(
                                        color: _getCategoryColor(category),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Text(
                              '\$${expense.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            initiallyExpanded: isExpanded,
                            onExpansionChanged: (expanded) {
                              setState(() {
                                _expandedIndex =
                                expanded ? originalIndex : null;
                              });
                            },
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.edit),
                                        label: const Text('Edit'),
                                        onPressed: () => _editExpense(originalIndex),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: expense.imagePath != null
                                        ? ElevatedButton.icon(
                                            icon: const Icon(Icons.image),
                                            label: const Text('View Receipt'),
                                            onPressed: () => _showReceiptImage(expense.imagePath!),
                                          )
                                        : ElevatedButton.icon(
                                            icon: const Icon(Icons.add_a_photo),
                                            label: const Text('Add Photo'),
                                            onPressed: () => _addReceiptPhoto(originalIndex),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
              childCount: _groupedExpenses.length,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.roseGold, //COLOR: plus button
        foregroundColor: AppColors.accent,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) =>
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('Add Expense Manually'),
                      onTap: () {
                        Navigator.pop(context);
                        _addExpense();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text('Take Receipt Photo'),
                      onTap: () async {
                        Navigator.pop(context);
                        final imagePath = await _takePicture();
                        if (imagePath != null) {
                          _addExpenseWithImage(imagePath);
                        }
                      },
                    ),
                  ],
                ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _getTimeFilterLabel(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.allTime:
        return 'All Time';
      case TimeFilter.thisYear:
        return 'This Year';
      case TimeFilter.last6Months:
        return 'Last 6 Months';
      case TimeFilter.last3Months:
        return 'Last 3 Months';
      case TimeFilter.thisMonth:
        return 'This Month';
      case TimeFilter.thisWeek:
        return 'This Week';
    }
  }


  Future<void> _editExpense(int index) async {
    final expense = _expenses[index];
    final nameController = TextEditingController(text: expense.name);
    final amountController = TextEditingController(text: expense.amount.toStringAsFixed(2));
    DateTime pickedDate = expense.date;
    ExpenseCategory selectedCategory = expense.category ?? ExpenseCategory.generalMerchandise;

    await showDialog(
      context: context,
      builder: (ctx) =>
          StatefulBuilder(
            builder: (ctx, setStateDialog) =>
                AlertDialog(
                  title: const Text('Edit Expense'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Description
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Description'),
                        ),
                        const SizedBox(height: 12),
                        // Amount
                        TextField(
                          controller: amountController,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '\$',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 12),
                        // Date picker
                        Row(
                          children: [
                            Text(DateFormat('MMM dd, yyyy').format(pickedDate)),
                            TextButton(
                              onPressed: () async {
                                final dt = await showDatePicker(
                                  context: ctx,
                                  initialDate: pickedDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (dt != null) setStateDialog(() => pickedDate = dt);
                              },
                              child: const Text('Change Date'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Category dropdown
                        DropdownButtonFormField<ExpenseCategory>(
                          value: selectedCategory,
                          items: ExpenseCategory.values.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(_getCategoryLabel(c)),
                            );
                          }).toList(),
                          decoration: const InputDecoration(labelText: 'Category'),
                          onChanged: (c) => setStateDialog(() => selectedCategory = c!),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final amt = double.tryParse(amountController.text) ?? 0;
                        if (name.isEmpty || amt <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid name and amount')),
                          );
                          return;
                        }

                        try {
                          final purchases = await _dbHelper.getAllPurchases();
                          final matchingPurchase = purchases.firstWhere(
                            (p) =>
                                p['name'] == expense.name &&
                                p['price'] == expense.amount &&
                                p['date'] == expense.date.toString(),
                          );

                          final updatedPurchase = Purchase(
                            id: matchingPurchase['id'],
                            name: name,
                            date: pickedDate.toIso8601String(),
                            price: amt,
                            category: selectedCategory.toString().split('.').last,
                            imagePath: expense.imagePath,
                          );

                          await _dbHelper.updatePurchase(updatedPurchase.toMap());
                          await _loadExpenses();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Expense updated successfully!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error updating expense: $e')),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _addReceiptPhoto(int index) async {
    final expense = _expenses[index];
    final imagePath = await _takePicture();
    
    if (imagePath != null) {
      try {
        final purchases = await _dbHelper.getAllPurchases();
        final matchingPurchase = purchases.firstWhere(
          (p) =>
              p['name'] == expense.name &&
              p['price'] == expense.amount &&
              p['date'] == expense.date.toString(),
        );

        final updatedPurchase = Purchase(
          id: matchingPurchase['id'],
          name: expense.name,
          date: expense.date.toString(),
          price: expense.amount,
          category: expense.category.toString().split('.').last,
          imagePath: imagePath,
        );

        await _dbHelper.updatePurchase(updatedPurchase.toMap());
        await _loadExpenses();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt photo added successfully!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding receipt photo: $e')),
        );
      }
    }
  }

  Future<void> _addExpenseWithImage(String imagePath) async {
    setState(() => _isLoading = true);

    late final ReceiptData data;
    try {
      data = await _veryfi.scanReceipt(imagePath);
    } on StateError catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;                      // ← after this, nothing else runs on error
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR failed: $e')),
      );
      return;                      // ← same here
    }
    setState(() => _isLoading = false);

    final nameController = TextEditingController(text: data.vendor);
    final amountController =
    TextEditingController(text: (data.total ?? 0).toStringAsFixed(2));
    DateTime pickedDate = data.date ?? DateTime.now();
    ExpenseCategory selectedCategory = ExpenseCategory.generalMerchandise;

    await showDialog(
      context: context,
      builder: (ctx) =>
          StatefulBuilder(
            builder: (ctx, setStateDialog) =>
                AlertDialog(
                  title: const Text('Confirm Receipt Details'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Description
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                              labelText: 'Description'),
                        ),
                        const SizedBox(height: 12),
                        // Amount
                        TextField(
                          controller: amountController,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '\$',
                          ),
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 12),
                        // Date picker
                        Row(
                          children: [
                            Text(DateFormat('MMM dd, yyyy').format(pickedDate)),
                            TextButton(
                              onPressed: () async {
                                final dt = await showDatePicker(
                                  context: ctx,
                                  initialDate: pickedDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (dt != null) setStateDialog(() =>
                                pickedDate = dt);
                              },
                              child: const Text('Change Date'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Category dropdown
                        DropdownButtonFormField<ExpenseCategory>(
                          value: selectedCategory,
                          items: ExpenseCategory.values.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(_getCategoryLabel(c)),
                            );
                          }).toList(),
                          decoration: const InputDecoration(
                              labelText: 'Category'),
                          onChanged: (c) =>
                              setStateDialog(() => selectedCategory = c!),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final amt = double.tryParse(amountController.text) ?? 0;
                        if (name.isEmpty || amt <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please enter a valid name and amount')),
                          );
                          return;
                        }
                        final purchase = Purchase(
                          name: name,
                          date: pickedDate.toIso8601String(),
                          price: amt,
                          category: selectedCategory
                              .toString()
                              .split('.')
                              .last,
                          imagePath: imagePath,
                        );
                        await DatabaseHelper.instance.createPurchase(
                            purchase.toMap());
                        await _loadExpenses();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Receipt added successfully!')),
                        );
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }
}

class AddExpenseSheet extends StatefulWidget {
  final Function(ExpenseEntry) onAdd;

  const AddExpenseSheet({
    super.key,
    required this.onAdd,
  });

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _amountError;
  ExpenseCategory _selectedCategory = ExpenseCategory.generalMerchandise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: 'Amount',
              border: const OutlineInputBorder(),
              prefixText: '\$',
              errorText: _amountError,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (value) {
              setState(() {
                if (value.isEmpty) {
                  _amountError = null;
                } else if (double.tryParse(value) == null) {
                  _amountError = 'Please enter a valid number';
                } else if (double.parse(value) <= 0) {
                  _amountError = 'Amount must be greater than 0';
                } else {
                  _amountError = null;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ExpenseCategory>(
            value: _selectedCategory,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: ExpenseCategory.values.map((category) {
              return DropdownMenuItem(
                value: category,
                child: Text(_getCategoryLabel(category)),
              );
            }).toList(),
            onChanged: (ExpenseCategory? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCategory = newValue;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
              ),
              TextButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                },
                child: const Text('Select Date'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }

              final amount = double.tryParse(_amountController.text);
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount')),
                );
                return;
              }

              widget.onAdd(
                ExpenseEntry(
                  name: _nameController.text,
                  amount: amount,
                  date: _selectedDate,
                  category: _selectedCategory,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Add Expense'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getCategoryLabel(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.groceries:
        return 'Groceries';
      case ExpenseCategory.dining:
        return 'Dining';
      case ExpenseCategory.transportation:
        return 'Transportation';
      case ExpenseCategory.healthcare:
        return 'Healthcare';
      case ExpenseCategory.clothing:
        return 'Clothing';
      case ExpenseCategory.electronics:
        return 'Electronics';
      case ExpenseCategory.homeMaintenance:
        return 'Home Maintenance';
      case ExpenseCategory.onlineShopping:
        return 'Online Shopping';
      case ExpenseCategory.travel:
        return 'Travel';
      case ExpenseCategory.entertainment:
        return 'Entertainment';
      case ExpenseCategory.generalMerchandise:
        return 'General Merchandise';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

class ExpenseEntry {
  final String name;
  final double amount;
  final DateTime date;
  final ExpenseCategory? category;
  final String? imagePath;

  ExpenseEntry({
    required this.name,
    required this.amount,
    required this.date,
    this.category,
    this.imagePath,
  });
}

