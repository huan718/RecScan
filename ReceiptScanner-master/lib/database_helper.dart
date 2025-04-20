import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const int _version = 2;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('purchases.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      final dbPath = await getApplicationDocumentsDirectory();
      final path = join(dbPath.path, filePath);

      return await openDatabase(
        path,
        version: _version,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      );
    } catch (e) {
      print('Error initializing database: $e');
      rethrow;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE purchases(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          date TEXT NOT NULL,
          price REAL NOT NULL,
          category TEXT NOT NULL,
          imagePath TEXT
        )
      ''');
      print('Database table created successfully');
    } catch (e) {
      print('Error creating database: $e');
      rethrow;
    }
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    try {
      if (oldVersion < 2) {
        // For version 2, we need to add the imagePath column
        await db.execute('ALTER TABLE purchases ADD COLUMN imagePath TEXT');
        print('Database upgraded to version 2');
      }
    } catch (e) {
      print('Error upgrading database: $e');
      rethrow;
    }
  }

  Future<int> createPurchase(Map<String, dynamic> row) async {
    try {
      final db = await instance.database;
      return await db.insert('purchases', row);
    } catch (e) {
      print('Error creating purchase: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllPurchases() async {
    try {
      final db = await instance.database;
      return await db.query('purchases');
    } catch (e) {
      print('Error getting all purchases: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPurchasesByCategory(String category) async {
    try {
      final db = await instance.database;
      return await db.query(
        'purchases',
        where: 'category = ?',
        whereArgs: [category],
      );
    } catch (e) {
      print('Error getting purchases by category: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPurchasesByDateRange(String startDate, String endDate) async {
    try {
      final db = await instance.database;
      return await db.query(
        'purchases',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [startDate, endDate],
      );
    } catch (e) {
      print('Error getting purchases by date range: $e');
      rethrow;
    }
  }

  Future<int> updatePurchase(Map<String, dynamic> row) async {
    try {
      final db = await instance.database;
      return await db.update(
        'purchases',
        row,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } catch (e) {
      print('Error updating purchase: $e');
      rethrow;
    }
  }

  Future<int> deletePurchase(int id) async {
    try {
      final db = await instance.database;
      return await db.delete(
        'purchases',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error deleting purchase: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      final db = await instance.database;
      await db.close();
    } catch (e) {
      print('Error closing database: $e');
      rethrow;
    }
  }

  Future<void> resetDatabase() async {
    try {
      final dbPath = await getApplicationDocumentsDirectory();
      final path = join(dbPath.path, 'purchases.db');
      
      // Close the database if it's open
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      
      // Delete the database file
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Reinitialize the database
      _database = await _initDB('purchases.db');
    } catch (e) {
      print('Error resetting database: $e');
      rethrow;
    }
  }

  Future<bool> checkDatabaseSchema() async {
    try {
      final db = await database;
      final result = await db.rawQuery('PRAGMA table_info(purchases)');
      final columns = result.map((row) => row['name'] as String).toList();
      
      // Check if all required columns exist
      final requiredColumns = ['id', 'name', 'date', 'price', 'category', 'imagePath'];
      final missingColumns = requiredColumns.where((col) => !columns.contains(col)).toList();
      
      if (missingColumns.isNotEmpty) {
        print('Missing columns: $missingColumns');
        return false;
      }
      
      return true;
    } catch (e) {
      print('Error checking database schema: $e');
      return false;
    }
  }
} 