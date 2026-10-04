import 'dart:convert';
import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:flutter/material.dart';
import 'crm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storagePath = await getAppStoragePath('crm_data.json');
  final service = await CrmService.init(storagePath);
  final server = StandardAppServer(schema: service.schema, store: service.store);
  try {
    await server.start();
  } catch (e) {
    stderr.writeln('CRM Server start ogohlantirish: $e');
  }

  final profileManager = await ProfileManager.create();
  final pluginManager = await PluginManager.create();

  runApp(CrmApp(
    service: service,
    profileManager: profileManager,
    pluginManager: pluginManager,
  ));
}

/// Moliya tizimiga yutilgan bitimdan kirim yozish (Localhost :8083 yoki Tarmoq IP :8083)
Future<bool> recordFinanceDealIncome({
  required String client,
  required num amount,
  required String note,
}) async {
  final payload = jsonEncode({
    'tool': 'finance_income',
    'params': {
      'amount': amount,
      'from': client,
      'category': 'Savdo/Bitim',
      'note': note,
    }
  });

  for (final host in ['127.0.0.1:8083', '192.168.8.104:8083']) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse('http://$host/execute'));
      req.headers.contentType = ContentType.json;
      req.write(payload);
      final resp = await req.close();
      client.close();
      if (resp.statusCode == 200) return true;
    } catch (_) {}
  }
  return false;
}

// ============================================================================
// DESIGN SYSTEM & THEME ARCHITECTURE (MIDNIGHT EXECUTIVE & LIGHT THEMES)
// ============================================================================
class CrmTheme {
  // Light Palette
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Dark Palette (Midnight Executive)
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkCard = Color(0xFF131B2E);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Primary Accent Colors (Teal / Emerald for CRM Deals)
  static const Color primary = Color(0xFF0D9488); // Teal 600
  static const Color primaryLight = Color(0xFF14B8A6); // Teal 500
  static const Color accentEmerald = Color(0xFF10B981); // Emerald 500
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentIndigo = Color(0xFF6366F1);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: primary,
      scaffoldBackgroundColor: lightBg,
      cardColor: lightCard,
      dividerColor: lightBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: Color(0xFFCCFBF1), // Teal 100
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: primaryLight,
      scaffoldBackgroundColor: darkBg,
      cardColor: darkCard,
      dividerColor: darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0F19),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF0B0F19),
        elevation: 0,
        indicatorColor: Color(0xFF134E4A), // Teal 900
      ),
    );
  }
}

// Global theme notifier for real-time switching
final ValueNotifier<ThemeMode> crmThemeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

class CrmApp extends StatelessWidget {
  const CrmApp({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
  });

  final CrmService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: crmThemeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'CRM & Savdo Voronkasi',
          debugShowCheckedModeBanner: false,
          theme: CrmTheme.light(),
          darkTheme: CrmTheme.dark(),
          themeMode: currentMode,
          home: CrmMainShell(
            service: service,
            profileManager: profileManager,
            pluginManager: pluginManager,
          ),
        );
      },
    );
  }
}

class CrmMainShell extends StatefulWidget {
  const CrmMainShell({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
  });

  final CrmService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;

  @override
  State<CrmMainShell> createState() => _CrmMainShellState();
}

class _CrmMainShellState extends State<CrmMainShell> {
  int _currentIndex = 0;
  final SecurityManager _security = SecurityManager();

  @override
  void initState() {
    super.initState();
    widget.service.store.addListener(_onStoreChanged);
    _syncUser();
  }

  @override
  void dispose() {
    widget.service.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _syncUser() {
    final cur = widget.profileManager.current;
    final matched = SecurityManager.defaultAccounts.firstWhere(
      (a) => a.id == cur.id,
      orElse: () => UserAccount(id: cur.id, name: cur.name, role: cur.role, department: cur.department),
    );
    _security.currentUser = matched;
  }

  void _switchUser(UserProfile profile) async {
    await widget.profileManager.switchProfile(profile);
    _syncUser();
    if (mounted) setState(() {});
  }

  void _openAiLeadAssistant(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CrmAiAssistantSheet(
        pluginManager: widget.pluginManager,
        service: widget.service,
        security: _security,
        onLeadCreated: () => setState(() => _currentIndex = 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.service.store.all;
    final activeCount = all.where((e) => e.status == 'new' || e.status == 'lead' || e.status == 'contacted' || e.status == 'talk').length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CrmTheme.darkBg : CrmTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? CrmTheme.darkBg : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: CrmTheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.people_alt_rounded, color: CrmTheme.primaryLight, size: 20),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CRM & Savdo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? CrmTheme.darkText : CrmTheme.lightText,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ':8082 • ${_security.currentUser.name.split(' ').first}',
                      style: TextStyle(fontSize: 10, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Dark/Light Theme Quick Toggle
          IconButton(
            tooltip: isDark ? "Kunduzgi rejim (Light)" : "Tungi rejim (Dark)",
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
              color: isDark ? const Color(0xFFFDE047) : const Color(0xFF64748B),
              size: 20,
            ),
            onPressed: () {
              crmThemeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),

          // Plagin: O'zbekcha AI Assistent
          if (widget.pluginManager.isPluginActive('plugin_uzbek_ai'))
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: Color(0xFFA855F7), size: 20),
              tooltip: "O'zbekcha AI Bitim Ochish",
              onPressed: () => _openAiLeadAssistant(context),
            ),

          // User Role Avatar Pill
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: CrmTheme.primary,
                  child: Text(
                    _security.currentUser.name.isNotEmpty ? _security.currentUser.name[0] : 'U',
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _security.currentUser.role.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isDark ? CrmTheme.darkText : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Mijozlar Ro'yxati (Core List)
          CrmLeadsTab(
            service: widget.service,
            security: _security,
            pluginManager: widget.pluginManager,
            onGoToCreate: () => setState(() => _currentIndex = 1),
          ),
          // Tab 1: Mijoz Qo'shish (Core Create Form)
          CrmCreateLeadTab(
            service: widget.service,
            security: _security,
            onLeadCreated: () => setState(() => _currentIndex = 0),
          ),
          // Tab 2: Profil & Sozlamalar (Core Profile & Settings)
          CrmProfileTab(
            service: widget.service,
            profileManager: widget.profileManager,
            pluginManager: widget.pluginManager,
            onProfileChanged: _switchUser,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Icons.people_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.people_rounded),
            label: 'Mijozlar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_add_alt_outlined),
            selectedIcon: Icon(Icons.person_add_alt_1_rounded),
            label: 'Mijoz Qo\'shish',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 0: MIJOZLAR RO'YXATI (MOBILE FIRST)
// ============================================================================
class CrmLeadsTab extends StatefulWidget {
  const CrmLeadsTab({
    super.key,
    required this.service,
    required this.security,
    required this.onGoToCreate,
    this.pluginManager,
  });

  final CrmService service;
  final SecurityManager security;
  final VoidCallback onGoToCreate;
  final PluginManager? pluginManager;

  @override
  State<CrmLeadsTab> createState() => _CrmLeadsTabState();
}

class _CrmLeadsTabState extends State<CrmLeadsTab> {
  String _stageFilter = 'all'; // all, new, contacted, won, lost
  String _search = '';

  List<Entity> get _leads {
    var items = widget.service.store.all;

    if (_stageFilter != 'all') {
      if (_stageFilter == 'new') {
        items = items.where((e) => e.status == 'new' || e.status == 'lead').toList();
      } else if (_stageFilter == 'contacted') {
        items = items.where((e) => e.status == 'contacted' || e.status == 'talk').toList();
      } else {
        items = items.where((e) => e.status == _stageFilter).toList();
      }
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase().trim();
      items = items.where((e) {
        final name = e.name.toLowerCase();
        final phone = (e.meta['phone'] ?? '').toString().toLowerCase();
        final prod = (e.meta['product'] ?? e.meta['company'] ?? '').toString().toLowerCase();
        final assigned = (e.meta['assigned_to'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || prod.contains(q) || assigned.contains(q);
      }).toList();
    }

    return items;
  }

  void _updateStage(Entity lead, String nextStage) async {
    final tool = widget.service.schema.tools.firstWhere(
      (t) => t.name == 'crm_lead_stage' || t.name == 'crm_stage',
    );
    await tool.handler({'id': lead.id, 'name': lead.name, 'stage': nextStage});

    // Agar bitim yutilsa (won), moliyaga avtomatik kirim
    if (nextStage == 'won') {
      final amount = UzbekNlp.parseNumber(lead.meta['deal_amount'] ?? lead.meta['budget']).toDouble();
      final product = lead.meta['product'] ?? lead.meta['company'] ?? 'Xizmat';

      // 1. Ekotizim Voqealar Shinası (EventBus) orqali e'lon qilish
      await EventBus.instance.publish(EcosystemEvent(
        name: 'crm_lead_won',
        sourceApp: 'crm',
        payload: {
          'lead_id': lead.id,
          'lead_name': lead.name,
          'product': '$product',
          'budget': amount,
        },
      ));

      // 2. Mahalliy zaxira yozish
      if (amount > 0) {
        await recordFinanceDealIncome(
          client: lead.name,
          amount: amount,
          note: 'CRM bitim yakunlandi: $product',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${lead.name}" bitimi yutildi! Moliyaga ${amount > 0 ? "$amount so'm" : ""} kirim qilindi.')),
        );
      }
    }

    if (mounted) setState(() {});
  }

  void _deleteLead(Entity lead) async {
    if (widget.security.currentUser.role != UserRole.director) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Faqat direktor mijoz yozuvini o\'chira oladi.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mijozni o\'chirish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Haqiqatdan ham "${lead.name}" mijozini butunlay o\'chirmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.service.store.delete(lead.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${lead.name}" o\'chirildi.')),
        );
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leads = _leads;
    final all = widget.service.store.all;
    final newCount = all.where((e) => e.status == 'new' || e.status == 'lead').length;
    final contactedCount = all.where((e) => e.status == 'contacted' || e.status == 'talk').length;
    final wonCount = all.where((e) => e.status == 'won').length;
    final lostCount = all.where((e) => e.status == 'lost').length;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          children: [
            // Top Command Header (Mobile First)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? CrmTheme.darkCard : Colors.white,
                border: Border(bottom: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0), width: 1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Search box
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Mijoz, telefon yoki mahsulot...',
                              hintStyle: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 20, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, size: 16, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                                      onPressed: () => setState(() => _search = ''),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            style: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add Button
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: CrmTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                        tooltip: "Yangi mijoz qo'shish",
                        onPressed: widget.onGoToCreate,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Filter Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill('all', 'Barchasi', all.length, isDark),
                        const SizedBox(width: 6),
                        _buildFilterPill('new', 'Yangi', newCount, isDark),
                        const SizedBox(width: 6),
                        _buildFilterPill('contacted', 'Muzokara', contactedCount, isDark),
                        const SizedBox(width: 6),
                        _buildFilterPill('won', 'Yutildi', wonCount, isDark),
                        const SizedBox(width: 6),
                        _buildFilterPill('lost', 'Yo\'qotildi', lostCount, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Savdo Voronkasi (Funnel Slot)
            if (widget.pluginManager?.isPluginActive('plugin_crm_funnel') != false)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D2825) : const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? const Color(0xFF115E59) : const Color(0xFFCCFBF1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_alt_rounded, size: 16, color: CrmTheme.primaryLight),
                        const SizedBox(width: 6),
                        const Text(
                          'Savdo Voronkasi (Funnel Plagini)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: CrmTheme.primaryLight),
                        ),
                        const Spacer(),
                        Text(
                          'Konversiya: ${all.isNotEmpty ? ((wonCount / all.length) * 100).toInt() : 0}%',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: CrmTheme.primaryLight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _FunnelStage(label: 'Yangi', count: newCount, color: const Color(0xFF3B82F6), isDark: isDark)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_right_alt_rounded, size: 16, color: isDark ? CrmTheme.darkTextMuted : Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(child: _FunnelStage(label: 'Muzokara', count: contactedCount, color: const Color(0xFFF59E0B), isDark: isDark)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_right_alt_rounded, size: 16, color: isDark ? CrmTheme.darkTextMuted : Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(child: _FunnelStage(label: 'Yutildi', count: wonCount, color: const Color(0xFF10B981), isDark: isDark)),
                      ],
                    ),
                  ],
                ),
              ),

            // Deals List
            Expanded(
              child: leads.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.people_outline_rounded, size: 32, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Mijozlar topilmadi',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Filtrni o\'zgartiring yoki yangi mijoz / bitim kiriting.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: widget.onGoToCreate,
                              style: FilledButton.styleFrom(backgroundColor: CrmTheme.primary),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Yangi Mijoz Qo\'shish'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      itemCount: leads.length,
                      itemBuilder: (ctx, idx) => _buildLeadCard(leads[idx], isDark),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String key, String label, int count, bool isDark) {
    final selected = _stageFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _stageFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? CrmTheme.primary
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? CrmTheme.primary
                : (isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : (isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569)),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.2)
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? Colors.white
                      : (isDark ? CrmTheme.darkText : const Color(0xFF334155)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadCard(Entity lead, bool isDark) {
    final status = lead.status;
    final phone = lead.meta['phone'] ?? 'Raqam kiritilmagan';
    final product = lead.meta['product'] ?? lead.meta['company'] ?? 'Umumiy';
    final budget = UzbekNlp.parseNumber(lead.meta['deal_amount'] ?? lead.meta['budget']);
    final assigned = lead.meta['assigned_to'] ?? 'Menejer';
    final isDirector = widget.security.currentUser.role == UserRole.director;

    Color stageColor;
    String stageText;
    if (status == 'won') {
      stageColor = const Color(0xFF10B981);
      stageText = 'Yutildi ✅';
    } else if (status == 'lost') {
      stageColor = const Color(0xFFEF4444);
      stageText = 'Yo\'qotildi ❌';
    } else if (status == 'contacted' || status == 'talk') {
      stageColor = const Color(0xFFF59E0B);
      stageText = 'Muzokara 💬';
    } else {
      stageColor = const Color(0xFF3B82F6);
      stageText = 'Yangi Lid 🆕';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? CrmTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Name and Stage Badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    lead.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stageColor.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: stageColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    stageText,
                    style: TextStyle(color: stageColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                if (isDirector) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: isDark ? CrmTheme.darkTextMuted : Colors.grey),
                    onPressed: () => _deleteLead(lead),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Chips Row: Assignee, Product, Budget, Phone
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Mas'ul
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 8,
                        backgroundColor: CrmTheme.primary,
                        child: Text(
                          assigned.toString().isNotEmpty ? assigned.toString()[0] : 'X',
                          style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$assigned',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF334155)),
                      ),
                    ],
                  ),
                ),

                // Mahsulot
                if (product.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '$product',
                          style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),

                // Byudjet Summasi
                if (budget > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on_outlined, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          '+${budget.toInt()} so\'m',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),

                // Telefon
                if (phone.isNotEmpty && phone != 'Raqam kiritilmagan')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_outlined, size: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '$phone',
                          style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons
            if (status == 'lead' || status == 'new')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _updateStage(lead, 'talk'),
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: const Text('Muzokara Boshlash', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: CrmTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              )
            else if (status == 'contacted' || status == 'talk')
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStage(lead, 'lost'),
                      icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                      label: const Text('Rad etish', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA)),
                        backgroundColor: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: () => _updateStage(lead, 'won'),
                      icon: const Icon(Icons.emoji_events_rounded, size: 15, color: Colors.white),
                      label: const Text('Bitimni Yutish', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              )
            else if (status == 'won')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bitim Yutildi & Moliyaga kassa kirimi kiritildi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (status == 'lost')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Mijoz bitimni rad etdi yoki bekor qilindi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                        ),
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
}

// ============================================================================
// TAB 1: MIJOZ QO'SHISH (CORE CREATE FORM - MOBILE FIRST)
// ============================================================================
class CrmCreateLeadTab extends StatefulWidget {
  const CrmCreateLeadTab({
    super.key,
    required this.service,
    required this.security,
    required this.onLeadCreated,
  });

  final CrmService service;
  final SecurityManager security;
  final VoidCallback onLeadCreated;

  @override
  State<CrmCreateLeadTab> createState() => _CrmCreateLeadTabState();
}

class _CrmCreateLeadTabState extends State<CrmCreateLeadTab> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+998 90 ');
  final _productController = TextEditingController();
  final _budgetController = TextEditingController(text: '5000000');
  final _noteController = TextEditingController();
  String _selectedAssignee = 'Vali';

  final List<String> _assignees = ['Vali', 'Ali', 'Sardor'];

  void _addPreset(String name, String phone, String prod, String budget) {
    _nameController.text = name;
    _phoneController.text = phone;
    _productController.text = prod;
    _budgetController.text = budget;
    setState(() {});
  }

  void _saveLead() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iltimos, mijoz nomini kiriting.')),
      );
      return;
    }

    final budget = UzbekNlp.parseNumber(_budgetController.text.trim());

    final tool = widget.service.schema.tools.firstWhere(
      (t) => t.name == 'crm_lead_add' || t.name == 'crm_add',
    );
    await tool.handler({
      'name': name,
      'phone': _phoneController.text.trim(),
      'product': _productController.text.trim().isEmpty ? 'Umumiy' : _productController.text.trim(),
      'company': _productController.text.trim().isEmpty ? name : _productController.text.trim(),
      'deal_amount': budget,
      'budget': budget,
      'assigned_to': _selectedAssignee,
      'note': _noteController.text.trim(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" muvaffaqiyatli saqlandi!')),
      );
      _nameController.clear();
      _productController.clear();
      _noteController.clear();
      widget.onLeadCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yangi Bitim & Mijoz Ochish',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Voronkaga yangi korxona kiritish, mahsulot va kutilayotgan byudjet',
                style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),

              // Hero AI Assistant Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF311042)]
                        : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFF818CF8), size: 18),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'O\'zbekcha AI Bitim Ochish',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : const Color(0xFF312E81),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('AUTO NLP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tabiiy tilda yozing: AI mijoz nomi, telefon va kutilayotgan byudjetni o\'zi avtomat ajratib oladi.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick Presets
              Text(
                'Tezkor namunalar (1-klikda to\'ldirish):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPresetChip('⚡ Akfa Korxona (5 mln)', () => _addPreset('Akfa Korxona', '+998 90 123 45 67', 'Plastik profil', '5000000'), isDark),
                  _buildPresetChip('🎯 Artel Zavod (12 mln)', () => _addPreset('Artel Zavod', '+998 91 987 65 43', 'Elektronika', '12000000'), isDark),
                  _buildPresetChip('🚀 Uzum Market (3.5 mln)', () => _addPreset('Uzum Market', '+998 93 555 44 33', 'Yetkazib berish', '3500000'), isDark),
                ],
              ),
              const SizedBox(height: 20),

              // Form Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? CrmTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mijoz Nomi
                    Text('Mijoz / Korxona Nomi *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 14, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
                      decoration: InputDecoration(
                        hintText: 'Masalan: Smart Savdo MCHJ',
                        hintStyle: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mas'ul Sotuvchi Xodim
                    Text('Mas\'ul Sotuvchi *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    Row(
                      children: _assignees.map((emp) {
                        final isSel = _selectedAssignee == emp;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedAssignee = emp),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? CrmTheme.primary.withValues(alpha: isDark ? 0.25 : 0.1)
                                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel
                                      ? CrmTheme.primary
                                      : (isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                                  width: isSel ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isSel ? CrmTheme.primary : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                    child: Text(
                                      emp[0],
                                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    emp,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                      color: isSel
                                          ? (isDark ? Colors.white : CrmTheme.primary)
                                          : (isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Byudjet Summasi
                    Text('Bitim Byudjeti (UZS)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _budgetController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF10B981) : const Color(0xFF047857)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20, color: Color(0xFF10B981)),
                        suffixText: 'so\'m',
                        suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mahsulot yoki Xizmat turi
                    Text('Mahsulot yoki Xizmat *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _productController,
                      style: TextStyle(fontSize: 14, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
                      decoration: InputDecoration(
                        hintText: 'Masalan: IT Dasturiy ta\'minot / Qurilish',
                        hintStyle: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Telefon raqami
                    Text('Telefon Raqami', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      style: TextStyle(fontSize: 14, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Izoh
                    Text('Dastlabki Izoh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      style: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
                      decoration: InputDecoration(
                        hintText: 'Mijoz talablari va dastlabki muzokara mazmuni...',
                        hintStyle: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _saveLead,
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const Text('Mijozni Ro\'yxatga Olish', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: CrmTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap, bool isDark) {
    return ActionChip(
      onPressed: onTap,
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? CrmTheme.darkText : const Color(0xFF334155))),
      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      side: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

// ============================================================================
// TAB 2: PROFIL & SOZLAMALAR (MOBILE FIRST & ZERO MOCK METRICS)
// ============================================================================
class CrmProfileTab extends StatefulWidget {
  const CrmProfileTab({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
    required this.onProfileChanged,
  });

  final CrmService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;
  final ValueChanged<UserProfile> onProfileChanged;

  @override
  State<CrmProfileTab> createState() => _CrmProfileTabState();
}

class _CrmProfileTabState extends State<CrmProfileTab> {
  UserProfile get _profile => widget.profileManager.current;
  int _activeSegment = 0; // 0: Rollar (RBAC), 1: Plaginlar, 2: Tizim

  @override
  Widget build(BuildContext context) {
    final plugins = widget.pluginManager.getAllPlugins();
    final all = widget.service.store.all;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Real Dynamic Metrics (Zero Synthetic Data)
    final totalClients = all.length;
    final wonList = all.where((e) => e.status == 'won').toList();
    final lostList = all.where((e) => e.status == 'lost').toList();
    final activePipelineList = all.where((e) => e.status != 'won' && e.status != 'lost').toList();

    num wonRevenue = 0;
    for (final c in wonList) {
      wonRevenue += UzbekNlp.parseNumber(c.meta['deal_amount'] ?? c.meta['budget']);
    }

    num activePipeline = 0;
    for (final c in activePipelineList) {
      activePipeline += UzbekNlp.parseNumber(c.meta['deal_amount'] ?? c.meta['budget']);
    }

    final finished = wonList.length + lostList.length;
    final convRate = finished > 0
        ? ((wonList.length / finished) * 100).toStringAsFixed(1)
        : (totalClients > 0 ? ((wonList.length / totalClients) * 100).toStringAsFixed(1) : '0.0');

    String wonFormatted;
    if (wonRevenue >= 1000000) {
      wonFormatted = '${(wonRevenue / 1000000).toStringAsFixed(1)}M UZS';
    } else if (wonRevenue >= 1000) {
      wonFormatted = '${(wonRevenue / 1000).toInt()}k UZS';
    } else {
      wonFormatted = '${wonRevenue.toInt()} UZS';
    }

    String pipelineFormatted;
    if (activePipeline >= 1000000) {
      pipelineFormatted = '${(activePipeline / 1000000).toStringAsFixed(1)}M UZS';
    } else if (activePipeline >= 1000) {
      pipelineFormatted = '${(activePipeline / 1000).toInt()}k UZS';
    } else {
      pipelineFormatted = '${activePipeline.toInt()} UZS';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Executive Profile Card
              Container(
                decoration: BoxDecoration(
                  color: isDark ? CrmTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Accent Line
                    Container(
                      height: 4,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF10B981)],
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: CrmTheme.primary,
                                    child: Text(
                                      _profile.name[0],
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: isDark ? CrmTheme.darkCard : Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _profile.name,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF3B82F6)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_profile.department} • Axion Software',
                                      style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: CrmTheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _profile.role.name.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: CrmTheme.primaryLight),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Divider(height: 1, color: isDark ? CrmTheme.darkBorder : const Color(0xFFF1F5F9)),
                          const SizedBox(height: 12),

                          // Contact Info
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.mail_outline_rounded, size: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                                  const SizedBox(width: 5),
                                  Text(
                                    _profile.email,
                                    style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(Icons.phone_outlined, size: 13, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                                  const SizedBox(width: 5),
                                  Text(
                                    _profile.phone,
                                    style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Dark/Light Theme Switcher Tile
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                  size: 18,
                                  color: isDark ? const Color(0xFF818CF8) : const Color(0xFFD97706),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    isDark ? 'Tungi rejim (Dark Mode)' : 'Kunduzgi rejim (Light Mode)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: isDark,
                                  activeTrackColor: CrmTheme.primary,
                                  onChanged: (val) {
                                    crmThemeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4 Dynamic Live Metric Cards
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'Mijozlar',
                      '$totalClients ta',
                      '${wonList.length} ta yutilgan',
                      const Color(0xFF3B82F6),
                      Icons.people_alt_outlined,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      'Konversiya',
                      '$convRate%',
                      'Bitimlar muvaffaqiyati',
                      const Color(0xFF10B981),
                      Icons.trending_up_rounded,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'Yutilgan Savdo',
                      wonFormatted,
                      'Kassaga kirim qilingan',
                      const Color(0xFF10B981),
                      Icons.monetization_on_outlined,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      'Voronka Qiymati',
                      pipelineFormatted,
                      'Faol muzokaralar',
                      const Color(0xFF8B5CF6),
                      Icons.account_balance_wallet_outlined,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Segment Navigation Tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    _buildSegmentButton(0, 'Rollar', Icons.badge_outlined, isDark),
                    _buildSegmentButton(1, 'Plaginlar (${plugins.length})', Icons.extension_outlined, isDark),
                    _buildSegmentButton(2, 'Tizim', Icons.dns_outlined, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Active Segment Content
              if (_activeSegment == 0)
                _buildRbacSection(isDark)
              else if (_activeSegment == 1)
                _buildPluginsSection(plugins, isDark)
              else
                _buildInfrastructureSection(isDark),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentButton(int index, String title, IconData icon, bool isDark) {
    final active = _activeSegment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? CrmTheme.primaryLight
                    : (isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active
                      ? (isDark ? CrmTheme.darkText : const Color(0xFF0F172A))
                      : (isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRbacSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foydalanuvchi va Rolni Tanlash (RBAC)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        Text(
          'Tizim sinovi uchun istalgan akkauntga o\'tishingiz mumkin. Ruxsatlar darhol moslashadi.',
          style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        Column(
          children: UserProfile.defaultProfiles.map((p) {
            final isCurrent = p.id == _profile.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isCurrent
                    ? CrmTheme.primary.withValues(alpha: isDark ? 0.15 : 0.05)
                    : (isDark ? CrmTheme.darkCard : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrent
                      ? CrmTheme.primary
                      : (isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                  width: isCurrent ? 1.5 : 1,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: isCurrent ? CrmTheme.primary : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                  child: Icon(
                    p.role == UserRole.director ? Icons.shield_rounded : Icons.person_rounded,
                    color: isCurrent ? Colors.white : (isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                    size: 16,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.role.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFFDE047) : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${p.department} • Axion ID: #${p.id}',
                  style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                ),
                trailing: isCurrent
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: CrmTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Faol', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    : TextButton(
                        onPressed: () => widget.onProfileChanged(p),
                        child: const Text('O\'tish', style: TextStyle(fontSize: 12)),
                      ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPluginsSection(List<EcosystemPlugin> plugins, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Plaginlar Markazi (Microkernel Engine)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${plugins.where((p) => p.isEnabled).length} ta faol',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: plugins.map((plugin) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? CrmTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
              ),
              child: SwitchListTile(
                dense: true,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CrmTheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    plugin.id == 'plugin_uzbek_ai'
                        ? Icons.auto_awesome
                        : (plugin.id == 'plugin_crm_funnel'
                            ? Icons.filter_alt_rounded
                            : (plugin.id == 'plugin_ecosystem_bridge' ? Icons.sync_alt_rounded : Icons.extension_outlined)),
                    color: CrmTheme.primaryLight,
                    size: 18,
                  ),
                ),
                title: Text(
                  plugin.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  plugin.description,
                  style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B)),
                ),
                value: plugin.isEnabled,
                activeTrackColor: CrmTheme.primary,
                onChanged: (val) async {
                  await widget.pluginManager.togglePlugin(plugin.id, val);
                  setState(() {});
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInfrastructureSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tizim va Microservice Holati',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? CrmTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildMicroserviceRow('CRM Gateway API', ':8082', 'Online (Faol)', 'REST API /schema & /execute', true, isDark),
              Divider(height: 1, color: isDark ? CrmTheme.darkBorder : const Color(0xFFF1F5F9)),
              _buildMicroserviceRow('KPI Engine API', ':8081', 'Online (Faol)', 'Xodimlar kpi va bonuslar', true, isDark),
              Divider(height: 1, color: isDark ? CrmTheme.darkBorder : const Color(0xFFF1F5F9)),
              _buildMicroserviceRow('Moliya Hub', ':8083', 'Ulanishga tayyor', 'Bitim tushumlari kassa balansi', true, isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Xavfsiz Xotira (StandardStore v1.0)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '• Baza formati: JSON Lines (Fayl darajasidagi xavfsiz blokirovka)\n• Avtomatik zaxira nusxalash (Backup): Har 24 soatda faol\n• Kesh va xotira oqishi: 0 MB (Nol oqish kafolatlangan)',
                style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569), height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(String title, String val, String sub, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? CrmTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, size: 15, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicroserviceRow(String name, String port, String status, String note, bool isOnline, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        port,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(note, style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isOnline
                  ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1)
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOnline ? const Color(0xFF10B981) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// VORONKA BOSQICHI WIDGETI (FUNNEL STAGE)
// ============================================================================
class _FunnelStage extends StatelessWidget {
  const _FunnelStage({required this.label, required this.count, required this.color, required this.isDark});
  final String label;
  final int count;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Column(
        children: [
          Text('$count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ============================================================================
// PLAGIN: CRM AI BITIM YARATISH (MODAL BOTTOM SHEET)
// ============================================================================
class CrmAiAssistantSheet extends StatefulWidget {
  const CrmAiAssistantSheet({
    super.key,
    required this.pluginManager,
    required this.service,
    required this.security,
    required this.onLeadCreated,
  });

  final PluginManager pluginManager;
  final CrmService service;
  final SecurityManager security;
  final VoidCallback onLeadCreated;

  @override
  State<CrmAiAssistantSheet> createState() => _CrmAiAssistantSheetState();
}

class _CrmAiAssistantSheetState extends State<CrmAiAssistantSheet> {
  final _controller = TextEditingController(
    text: "Akmal bilan 15 000 000 so'mlik ERP Tizimi bo'yicha yangi bitim och, tel: +998901234567",
  );
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  void _analyze() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);

    // Natural Language Parsing for CRM Deal
    final budget = UzbekNlp.parseNumber(text).toDouble();
    String name = 'Mijoz';
    final nameMatch = RegExp(r'([A-ZА-ЯЁ][a-zа-яё]+)\s+bilan').firstMatch(text);
    if (nameMatch != null) {
      name = nameMatch.group(1) ?? 'Mijoz';
    } else {
      final words = text.split(' ');
      if (words.isNotEmpty) name = words.first;
    }

    String phone = '+998 90 000 00 00';
    final phoneMatch = RegExp(r'(\+?\d[\d\s-]{7,}\d)').firstMatch(text);
    if (phoneMatch != null) {
      phone = phoneMatch.group(1) ?? phone;
    }

    String product = 'Xizmat';
    if (text.toLowerCase().contains('erp')) {
      product = 'ERP Tizimi';
    } else if (text.toLowerCase().contains('mobil')) {
      product = 'Mobil Ilova';
    } else if (text.toLowerCase().contains('sayt') || text.toLowerCase().contains('veb')) {
      product = 'Veb-sayt';
    }

    setState(() {
      _isLoading = false;
      _result = {
        'name': name,
        'phone': phone,
        'product': product,
        'budget': budget > 0 ? budget : 5000000.0,
      };
    });
  }

  void _confirmAndCreate() async {
    if (_result == null) return;

    final tool = widget.service.schema.tools.firstWhere(
      (t) => t.name == 'crm_lead_add' || t.name == 'crm_add',
    );
    await tool.handler({
      'name': _result!['name'],
      'phone': _result!['phone'],
      'product': _result!['product'],
      'company': _result!['product'],
      'deal_amount': _result!['budget'],
      'budget': _result!['budget'],
      'assigned_to': widget.security.currentUser.name,
      'source': 'AI Assistent',
      'note': 'AI orqali tezkor ochilgan bitim',
    });

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${_result!['name']}" uchun yangi bitim ochildi!')),
      );
      widget.onLeadCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? CrmTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF818CF8), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Bitim & Mijoz Yaratish',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Tabiiy tilda yozing, AI mijoz va bitim byudjetini aniqlaydi',
                        style: TextStyle(fontSize: 11, color: isDark ? CrmTheme.darkTextMuted : Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: isDark ? CrmTheme.darkTextMuted : Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tezkor namunalar
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Akmal: 15 mln ERP Tizimi', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _controller.text = "Akmal bilan 15 000 000 so'mlik ERP Tizimi bo'yicha yangi bitim och, tel: +998901234567";
                    _analyze();
                  },
                ),
                ActionChip(
                  label: const Text('Bobur: 8 mln Mobil ilova', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _controller.text = "Bobur bilan 8 000 000 so'mlik Mobil ilova ishlab chiqish bitimi, tel: +998939876543";
                    _analyze();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _controller,
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: isDark ? CrmTheme.darkText : CrmTheme.lightText),
              decoration: InputDecoration(
                hintText: 'Masalan: Akmal bilan 15 mln so\'mlik ERP bo\'yicha yangi bitim och',
                hintStyle: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF94A3B8)),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? CrmTheme.darkBorder : const Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _analyze,
                icon: const Icon(Icons.psychology, size: 18),
                label: const Text('AI Bitimini Tahlil Qilish'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 6),
                        Text('Aniqlangan Bitim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981))),
                      ],
                    ),
                    Divider(height: 16, color: isDark ? CrmTheme.darkBorder : const Color(0xFFCCFBF1)),
                    Text('• Mijoz: ${_result!['name']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? CrmTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('• Telefon: ${_result!['phone']}', style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569))),
                    const SizedBox(height: 4),
                    Text('• Mahsulot/Xizmat: ${_result!['product']}', style: TextStyle(fontSize: 12, color: isDark ? CrmTheme.darkTextMuted : const Color(0xFF475569))),
                    const SizedBox(height: 4),
                    Text('• Byudjet: ${(_result!['budget'] as num).toInt()} so\'m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10B981))),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: FilledButton.icon(
                        onPressed: _confirmAndCreate,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Bitimni Ochish va Saqlash', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(backgroundColor: CrmTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
