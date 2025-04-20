import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../purchase.dart';
import 'home_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _dbHelper = DatabaseHelper.instance;
  List<Purchase> _purchases = [];
  bool _isLoading = true;
  TimeFilter _currentTimeFilter = TimeFilter.allTime;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final purchases = await _dbHelper.getAllPurchases();
      setState(() {
        _purchases = purchases.map((p) => Purchase.fromMap(p)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
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
  
  List<Purchase> get _filteredPurchases {
    final now = DateTime.now();
    return _purchases.where((purchase) {
      final purchaseDate = DateTime.parse(purchase.date);
      
      // Apply time filter
      switch (_currentTimeFilter) {
        case TimeFilter.allTime:
          return true;
        case TimeFilter.thisYear:
          return purchaseDate.year == now.year;
        case TimeFilter.last6Months:
          final sixMonthsAgo = DateTime(now.year, now.month - 6, now.day);
          return purchaseDate.isAfter(sixMonthsAgo);
        case TimeFilter.last3Months:
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return purchaseDate.isAfter(threeMonthsAgo);
        case TimeFilter.thisMonth:
          return purchaseDate.year == now.year && purchaseDate.month == now.month;
        case TimeFilter.thisWeek:
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          return purchaseDate.isAfter(startOfWeek);
      }
    }).toList();
  }
  
  Map<String, double> get _categoryTotals {
    final totals = <String, double>{};
    
    for (final purchase in _filteredPurchases) {
      final category = purchase.category;
      totals[category] = (totals[category] ?? 0) + purchase.price;
    }
    
    return totals;
  }
  
  Color _getCategoryColor(String category) {
    // Match the category colors from home_screen.dart
    switch (category.toLowerCase()) {
      case 'groceries':
        return Colors.green;
      case 'dining':
        return Colors.orange;
      case 'transportation':
        return Colors.blue;
      case 'healthcare':
        return Colors.red;
      case 'clothing':
        return Colors.purple;
      case 'electronics':
        return Colors.indigo;
      case 'homemaintenance':
        return Colors.brown;
      case 'onlineshopping':
        return Colors.teal;
      case 'travel':
        return Colors.amber;
      case 'entertainment':
        return Colors.pink;
      case 'generalmerchandise':
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Spending Overview',
                                style: TextStyle(
                                  fontSize: 20,
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
                          const SizedBox(height: 16),
                          const Text(
                            'Category Spending',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._buildCategoryList(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  List<Widget> _buildCategoryList() {
    final categoryTotals = _categoryTotals;
    
    if (categoryTotals.isEmpty) {
      return [const Text('No expenses recorded for this period')];
    }
    
    // Sort categories by amount spent (highest first)
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Calculate total for percentage
    final total = sortedCategories.fold<double>(
      0, (sum, entry) => sum + entry.value);
    
    return sortedCategories.map((entry) {
      final category = entry.key;
      final amount = entry.value;
      final percentage = (amount / total * 100).toStringAsFixed(1);
      
      // Format category name for display
      final displayName = category.split('').map((char) {
        if (char == char.toUpperCase() && category.indexOf(char) > 0) {
          return ' ${char.toLowerCase()}';
        }
        return char;
      }).join('');
      
      final formattedName = displayName[0].toUpperCase() + displayName.substring(1);
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(category),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formattedName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Text(
                  '\$${amount.toStringAsFixed(2)} ($percentage%)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: amount / total,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(_getCategoryColor(category)),
            ),
          ],
        ),
      );
    }).toList();
  }
}