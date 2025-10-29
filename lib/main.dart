import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'dart:io';
import 'dart:async';
import 'services/supabase_sync_service.dart';

Future<void> signInWithGoogle() async {
  final supabase = supa.Supabase.instance.client;

  await supabase.auth.signInWithOAuth(
    supa.OAuthProvider.google,
    redirectTo: 'io.supabase.portfolio://login-callback',
  );
}



const Color kMintGreen = Color(0xFFD4F4DD);

// Transaction Model
class Transaction {
  final String id;
  final String type; // 'Income' or 'Expense'
  final double amount;
  final String category;
  final String? name; // Investment name (nullable for backward compatibility)
  final String description;
  final DateTime date;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    this.name, // Made optional
    required this.description,
    required this.date,
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  // TODO: Replace with your Supabase project URL and anon key
  await supa.Supabase.initialize(
    url: 'https://ygegatjxgdvirpwfeqru.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlnZWdhdGp4Z2R2aXJwd2ZlcXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE0ODcxMzYsImV4cCI6MjA3NzA2MzEzNn0.mlYKMoEsvtykx6cdAcTOrn8uFo5r3XoZWVrCrX4uTGE',
  );
  
  // Initialize cloud sync
  await SupabaseSyncService.autoSync();
  
  runApp(const PortfolioApp());
}

class PortfolioApp extends StatelessWidget {
  const PortfolioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portfolio Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101010),
        primaryColor: const Color(0xFF6C63FF),
        fontFamily: 'Inter',
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  List<Transaction> _transactions = [];
  bool _isSignedIn = false;
  bool _isLoading = true;
  late final StreamSubscription<supa.AuthState> _authSubscription;

  List<Widget> get _screens => [
    HomeScreen(transactions: _transactions),
    TransactionsScreen(transactions: _transactions),
    const AnalyticsScreen(),
    ProfileScreen(
      onSignIn: _handleSignIn,
      onSignOut: _handleSignOut,
      isSignedIn: _isSignedIn,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _authSubscription = supa.Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      final signedInNow = session != null;
      if (mounted) {
        setState(() {
          _isSignedIn = signedInNow;
        });
      }
      if (signedInNow) {
        try {
          await SupabaseSyncService.syncAllData(_transactions);
          await _loadCloudData();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      // Check if user is signed in
      final isSignedIn = SupabaseSyncService.isSignedIn;
      setState(() {
        _isSignedIn = isSignedIn;
      });

      if (isSignedIn) {
        // Load data from cloud
        await _loadCloudData();
      } else {
        // Load local backup
        await _loadLocalData();
      }
    } catch (e) {
      print('Initialization error: $e');
      // Fallback to local data
      await _loadLocalData();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCloudData() async {
    try {
      final cloudData = await SupabaseSyncService.loadAllData();
      final transactions = (cloudData['transactions'] as List<dynamic>).cast<Transaction>();
      setState(() {
        _transactions = transactions;
      });
    } catch (e) {
      print('Failed to load cloud data: $e');
      await _loadLocalData();
    }
  }

  Future<void> _loadLocalData() async {
    try {
      final localTransactions = await SupabaseSyncService.loadLocalBackup();
      setState(() {
        _transactions = localTransactions;
      });
    } catch (e) {
      print('Failed to load local data: $e');
    }
  }

  void _addTransaction(Transaction transaction) async {
    setState(() {
      _transactions.insert(0, transaction); // Add at the beginning
    });

    // Save locally first
    await SupabaseSyncService.saveLocalBackup(_transactions);

    // If signed in, sync to cloud
    if (_isSignedIn) {
      try {
        await SupabaseSyncService.saveTransactions(_transactions);
      } catch (e) {
        print('Failed to sync to cloud: $e');
        // Show error to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved locally. Cloud sync failed: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSignIn() async {
    try {
      setState(() {
        _isLoading = true;
      });
      await SupabaseSyncService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await SupabaseSyncService.signOut();
      setState(() {
        _isSignedIn = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out successfully!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign out failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF101010),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFab9ff2)),
              ),
              SizedBox(height: 16),
              Text(
                'Loading your portfolio...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: _screens[_currentIndex],
      floatingActionButton: _currentIndex == 1 
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddTransactionScreen(),
                  ),
                );
                if (result != null && result is Transaction) {
                  _addTransaction(result);
                }
              },
              backgroundColor: const Color(0xFFab9ff2), // New color
              foregroundColor: Colors.white,
              elevation: 8,
              child: const Icon(Icons.add, size: 28),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        height: 95,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFA78BFA),
          unselectedItemColor: Colors.grey,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.swap_horiz_rounded),
              label: 'Transactions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// HOME SCREEN
class HomeScreen extends StatelessWidget {
  final List<Transaction> transactions;

  const HomeScreen({Key? key, required this.transactions}) : super(key: key);

  double _computeBalance() {
    double balance = 0;
    for (final t in transactions) {
      balance += t.type == 'Income' ? t.amount : -t.amount;
    }
    return balance;
  }

  double _computeSevenDayDelta() {
    final now = DateTime.now();
    double last7 = 0;
    for (final t in transactions) {
      if (now.difference(t.date).inDays < 7) {
        last7 += t.type == 'Income' ? t.amount : -t.amount;
      }
    }
    return last7;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (avatar + account + actions)
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFF2A2A2A),
                  child: Icon(Icons.park_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Account 1',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.settings, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Balance centered with growth chips
            Center(
              child: Column(
                children: [
                  Text(
                    '\$${_computeBalance().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: kMintGreen.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_computeSevenDayDelta() >= 0 ? '+' : ''}\$${_computeSevenDayDelta().toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: kMintGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: kMintGreen.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '7d change',
                          style: TextStyle(
                            color: kMintGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Wallet Growth (compact)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wallet Growth',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kMintGreen.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '+2.76%',
                          style: TextStyle(
                            color: kMintGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${_computeBalance().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              const FlSpot(0, 3),
                              const FlSpot(1, 4),
                              const FlSpot(2, 2.5),
                              const FlSpot(3, 3.5),
                              const FlSpot(4, 2),
                              const FlSpot(5, 4.5),
                              const FlSpot(6, 3),
                            ],
                            isCurved: true,
                            color: kMintGreen,
                            barWidth: 3,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: kMintGreen.withOpacity(0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Stats Grid
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Big Left Card
                    Expanded(
                      flex: 5,
                      // FIXED: Wrap the card with ConstrainedBox to set a size rule
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 240, // This is the smallest the card can be. Adjust as needed.
                        ),
                        child: _buildStatCard(
                          'Realized P&L',
                          '\$582.12',
                          '+12.3%',
                          const Color(0xFFFFF4E0),
                          Colors.black87,
                          percentageColor: Colors.green[800],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Two Stacked Right Cards
                    Expanded(
                      flex: 4, // Now, increasing this flex will work as you expect
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Unrealized',
                              '\$123.45',
                              '',
                              kMintGreen,
                              Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _buildStatCard(
                              'Top Mover',
                              'ETH +5%',
                              '',
                              const Color(0xFFFFFACD),
                              Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30), // Assets Section
            const Text(
              'Assets',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _buildAssetItem(
              'Ethereum',
              '1.2345 ETH',
              '\$2,345.67',
              '+2.5%',
              Colors.purple[300]!,
              'ETH',
              true,
            ),
            const SizedBox(height: 12),
            _buildAssetItem(
              'Bitcoin',
              '0.1234 BTC',
              '\$10,000.00',
              '-0.8%',
              Colors.orange[400]!,
              'BTC',
              false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label,
      String value,
      String percentage,
      Color bgColor,
      Color textColor, {
        Color? percentageColor,
        double? height,
      }) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textColor.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (percentage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              percentage,
              style: TextStyle(
                color: percentageColor ?? textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssetItem(
      String name,
      String amount,
      String value,
      String change,
      Color iconColor,
      String symbol,
      bool isPositive,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                symbol,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                change,
                style: TextStyle(
                  color: isPositive ? Colors.green[400] : Colors.red[400],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// TRANSACTIONS SCREEN
class TransactionsScreen extends StatelessWidget {
  final List<Transaction> transactions;
  
  const TransactionsScreen({Key? key, required this.transactions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Expanded(
                  child: Text(
                    'Transactions',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 64,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add your first transaction',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildTransactionCard(transaction),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    final isIncome = transaction.type == 'Income';
    final amountColor = isIncome ? Colors.green[400]! : Colors.red[400]!;
    final iconColor = isIncome ? Colors.green[400]! : Colors.red[400]!;
    final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.name ?? 'Unknown Investment',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.category,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(transaction.date),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                if (transaction.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    transaction.description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '-'}${transaction.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: amountColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                transaction.type,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    
    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '${difference} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// ANALYTICS SCREEN
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Expanded(
                  child: Text(
                    'Analytics',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 30),

            // Donut Chart
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 70,
                            sections: [
                              PieChartSectionData(
                                value: 25,
                                color: Colors.yellow[300]!,
                                radius: 30,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: 25,
                                color: Colors.pink[200]!,
                                radius: 30,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: 25,
                                color: Colors.cyan[300]!,
                                radius: 30,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: 25,
                                color: Colors.purple[200]!,
                                radius: 30,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Total Value',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '\$12,345',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildLegendItem('Stocks', Colors.yellow[300]!),
                  const SizedBox(height: 12),
                  _buildLegendItem('Crypto', Colors.cyan[300]!),
                  const SizedBox(height: 12),
                  _buildLegendItem('Real Estate', Colors.pink[200]!),
                  const SizedBox(height: 12),
                  _buildLegendItem('Bonds', Colors.purple[200]!),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Capital vs Profits
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Capital vs.\nProfits',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 100,
                          width: 100,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PieChart(
                                PieChartData(
                                  sectionsSpace: 0,
                                  centerSpaceRadius: 35,
                                  startDegreeOffset: -90,
                                  sections: [
                                    PieChartSectionData(
                                      value: 70,
                                      color: Colors.green[400]!,
                                      radius: 15,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      value: 30,
                                      color: const Color(0xFF1A1A1A),
                                      radius: 15,
                                      showTitle: false,
                                    ),
                                  ],
                                ),
                              ),
                              const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Profit',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    '\$5,678',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '+8%',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Inflows',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '\$15,000',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+10%',
                              style: TextStyle(
                                color: Colors.green[400],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Outflows',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '\$3,000',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '-5%',
                              style: TextStyle(
                                color: Colors.red[400],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Reinvestments
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reinvestments',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '\$2,000',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+2%',
                    style: TextStyle(
                      color: Colors.green[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// PROFILE SCREEN with Firebase Storage example
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;
  final bool isSignedIn;

  const ProfileScreen({
    Key? key,
    this.onSignIn,
    this.onSignOut,
    this.isSignedIn = false,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),

            // Authentication Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    widget.isSignedIn ? Icons.cloud_done : Icons.cloud_off,
                    size: 48,
                    color: widget.isSignedIn ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.isSignedIn ? 'Cloud Sync Active' : 'Sign in to sync data',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isSignedIn 
                        ? 'Your data is synced across all devices'
                        : 'Sign in with Google to backup and sync your portfolio data',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.isSignedIn ? widget.onSignOut : widget.onSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.isSignedIn 
                            ? Colors.red[600] 
                            : const Color(0xFFab9ff2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        widget.isSignedIn ? Icons.logout : Icons.login,
                      ),
                      label: Text(
                        widget.isSignedIn ? 'Sign Out' : 'Sign in with Google',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Keep profile simple; no image upload or extra cards
          ],
        ),
      ),
    );
  }

  
}

// ADD TRANSACTION SCREEN
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({Key? key}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedCategory = 'Stocks';
  String _selectedType = 'Expense'; // 'Income' or 'Expense'
  
  final List<String> _categories = [
    'Stocks',
    'Cryptocurrency',
    'Real Estate',
    'Mutual Funds',
    'ETFs',
    'Bonds',
    'Commodities',
    'REITs',
    'Options',
    'Futures',
    'Other',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Add Transaction',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Transaction Type Selection
                const Text(
                  'Transaction Type',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton('Income', Icons.arrow_downward, Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeButton('Expense', Icons.arrow_upward, Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Name Field
                const Text(
                  'Investment Name',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'e.g., Apple Inc., Bitcoin, Tesla',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an investment name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Amount Field
                const Text(
                  'Amount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an amount';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Category Selection
                const Text(
                  'Category',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A2A),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      items: _categories.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedCategory = newValue!;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Description Field
                const Text(
                  'Description (Optional)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Add a note...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 40),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saveTransaction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFab9ff2),
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Transaction',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton(String type, IconData icon, Color color) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              type,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveTransaction() {
    if (_formKey.currentState!.validate()) {
      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _selectedType,
        amount: double.parse(_amountController.text),
        category: _selectedCategory,
        name: _nameController.text,
        description: _descriptionController.text,
        date: DateTime.now(),
      );
      
      Navigator.pop(context, transaction);
    }
  }
}