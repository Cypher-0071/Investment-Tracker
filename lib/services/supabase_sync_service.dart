import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart';

class SupabaseSyncService {
  static final SupabaseClient _client = Supabase.instance.client;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  static User? get currentUser => _client.auth.currentUser;
  static bool get isSignedIn => currentUser != null;

  /// Sign in with Google
  static Future<User?> signInWithGoogle() async {
    try {
      // Use Supabase's built-in Google OAuth
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.portfolio://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      
      // Wait for the user to complete the OAuth flow
      // Note: Supabase will handle the redirect and sign in automatically
      return _client.auth.currentUser;
    } catch (e) {
      throw Exception('Google Sign-In failed: $e');
    }
  }

  /// Sign out
  static Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      await _googleSignIn.signOut();
      
      // Clear local data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  /// Save transactions to Supabase
  static Future<void> saveTransactions(List<Transaction> transactions) async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      final user = currentUser!;
      final transactionsData = transactions.map((transaction) => {
        'id': transaction.id,
        'type': transaction.type,
        'amount': transaction.amount,
        'category': transaction.category,
        'name': transaction.name,
        'description': transaction.description,
        'date': transaction.date.toIso8601String(),
        'user_id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();

      await _client.from('transactions').upsert(
        transactionsData,
        onConflict: 'id',
      );
    } catch (e) {
      throw Exception('Failed to save transactions: $e');
    }
  }

  /// Load transactions from Supabase
  static Future<List<Transaction>> loadTransactions() async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      final user = currentUser!;
      final response = await _client
          .from('transactions')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false);

      if (response.isEmpty) return [];

      return (response as List<dynamic>).map((data) => Transaction(
        id: data['id'],
        type: data['type'],
        amount: (data['amount'] as num).toDouble(),
        category: data['category'],
        name: data['name'],
        description: data['description'],
        date: DateTime.parse(data['date']),
      )).toList();
    } catch (e) {
      throw Exception('Failed to load transactions: $e');
    }
  }

  /// Save user profile data
  static Future<void> saveUserProfile({
    String? displayName,
    String? photoUrl,
    Map<String, dynamic>? additionalData,
  }) async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      final user = currentUser!;
      final profileData = {
        'id': user.id,
        'email': user.email,
        'display_name': displayName ?? user.userMetadata?['full_name'],
        'photo_url': photoUrl ?? user.userMetadata?['avatar_url'],
        'updated_at': DateTime.now().toIso8601String(),
        ...?additionalData,
      };

      await _client.from('profiles').upsert(
        profileData,
        onConflict: 'id',
      );
    } catch (e) {
      throw Exception('Failed to save user profile: $e');
    }
  }

  /// Load user profile data
  static Future<Map<String, dynamic>?> loadUserProfile() async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      final user = currentUser!;
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      return response as Map<String, dynamic>?;
    } catch (e) {
      throw Exception('Failed to load user profile: $e');
    }
  }

  /// Sync all data (transactions + profile)
  static Future<void> syncAllData(List<Transaction> transactions) async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      await Future.wait([
        saveTransactions(transactions),
        saveUserProfile(),
      ]);
    } catch (e) {
      throw Exception('Failed to sync data: $e');
    }
  }

  /// Load all data from cloud
  static Future<Map<String, dynamic>> loadAllData() async {
    if (!isSignedIn) throw Exception('User not signed in');
    
    try {
      final results = await Future.wait([
        loadTransactions(),
        loadUserProfile(),
      ]);

      return {
        'transactions': results[0] as List<Transaction>,
        'profile': results[1] as Map<String, dynamic>?,
      };
    } catch (e) {
      throw Exception('Failed to load all data: $e');
    }
  }

  /// Check if user has cloud data
  static Future<bool> hasCloudData() async {
    if (!isSignedIn) return false;
    
    try {
      final user = currentUser!;
      final response = await _client
          .from('transactions')
          .select('id')
          .eq('user_id', user.id)
          .limit(1);
      
      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Save data locally as backup
  static Future<void> saveLocalBackup(List<Transaction> transactions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = transactions.map((t) => {
        'id': t.id,
        'type': t.type,
        'amount': t.amount,
        'category': t.category,
        'name': t.name,
        'description': t.description,
        'date': t.date.millisecondsSinceEpoch,
      }).toList();
      
      await prefs.setString('local_transactions', jsonEncode(transactionsJson));
    } catch (e) {
      throw Exception('Failed to save local backup: $e');
    }
  }

  /// Load data from local backup
  static Future<List<Transaction>> loadLocalBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = prefs.getString('local_transactions');
      
      if (transactionsJson == null) return [];
      
      final List<dynamic> transactionsData = jsonDecode(transactionsJson);
      return transactionsData.map((data) => Transaction(
        id: data['id'],
        type: data['type'],
        amount: (data['amount'] as num).toDouble(),
        category: data['category'],
        name: data['name'],
        description: data['description'],
        date: DateTime.fromMillisecondsSinceEpoch(data['date']),
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Auto-sync when app starts
  static Future<void> autoSync() async {
    if (!isSignedIn) return;
    
    try {
      // Load local data first
      final localTransactions = await loadLocalBackup();
      
      // Check if cloud data exists
      final hasCloud = await hasCloudData();
      
      if (hasCloud) {
        // Load from cloud and merge with local
        final cloudTransactions = await loadTransactions();
        
        // Merge transactions (cloud takes priority for conflicts)
        final mergedTransactions = <Transaction>[];
        final cloudIds = cloudTransactions.map((t) => t.id).toSet();
        
        // Add cloud transactions
        mergedTransactions.addAll(cloudTransactions);
        
        // Add local transactions that don't exist in cloud
        for (final localTransaction in localTransactions) {
          if (!cloudIds.contains(localTransaction.id)) {
            mergedTransactions.add(localTransaction);
          }
        }
        
        // Save merged data locally
        await saveLocalBackup(mergedTransactions);
        
        // Sync to cloud
        await saveTransactions(mergedTransactions);
      } else {
        // No cloud data, upload local data
        if (localTransactions.isNotEmpty) {
          await saveTransactions(localTransactions);
        }
      }
    } catch (e) {
      print('Auto-sync failed: $e');
    }
  }
}

