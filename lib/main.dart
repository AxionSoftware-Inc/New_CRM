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
    return MaterialApp(
      title: 'CRM & Mijozlar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: CrmMainShell(
        service: service,
        profileManager: profileManager,
        pluginManager: pluginManager,
      ),
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
    final newCount = widget.service.store.all.where((e) => e.status == 'new' || e.status == 'contacted').length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.people_alt_outlined, color: Colors.teal, size: 24),
            const SizedBox(width: 8),
            const Text(
              'CRM & Mijozlar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _security.currentUser.role == UserRole.director
                    ? Colors.teal.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _security.currentUser.role == UserRole.director
                      ? Colors.teal.shade300
                      : Colors.blue.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _security.currentUser.role == UserRole.director ? Icons.shield : Icons.person,
                    size: 13,
                    color: _security.currentUser.role == UserRole.director
                        ? Colors.teal.shade800
                        : Colors.blue.shade800,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.profileManager.current.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _security.currentUser.role == UserRole.director
                          ? Colors.teal.shade900
                          : Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Plagin: O'zbekcha AI Assistent
          if (widget.pluginManager.isPluginActive('plugin_uzbek_ai'))
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: Colors.purple),
              tooltip: "O'zbekcha AI Bitim Ochish",
              onPressed: () => _openAiLeadAssistant(context),
            ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade400),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, size: 13, color: Colors.green),
                SizedBox(width: 5),
                Text(':8082', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
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
              isLabelVisible: newCount > 0,
              label: Text('$newCount'),
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: const Icon(Icons.people),
            label: 'Mijozlar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_add_alt_1_outlined),
            selectedIcon: Icon(Icons.person_add_alt_1),
            label: 'Mijoz Qo\'shish',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil & Sozlamalar',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 0: MIJOZLAR RO'YXATI (CORE LIST)
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
      items = items.where((e) => e.status == _stageFilter).toList();
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase().trim();
      items = items.where((e) {
        final name = e.name.toLowerCase();
        final phone = (e.meta['phone'] ?? '').toString().toLowerCase();
        final prod = (e.meta['product'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || prod.contains(q);
      }).toList();
    }

    return items;
  }

  void _updateStage(Entity lead, String nextStage) async {
    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'crm_lead_stage');
    await tool.handler({'id': lead.id, 'stage': nextStage});

    // Agar bitim yutilsa (won), moliyaga avtomatik kirim
    if (nextStage == 'won') {
      final amount = UzbekNlp.parseNumber(lead.meta['budget']).toDouble();

      // 1. Ekotizim Voqealar Shinası (EventBus) orqali e'lon qilish -> Bridge plaginini avtomat ishga tushiradi
      await EventBus.instance.publish(EcosystemEvent(
        name: 'crm_lead_won',
        sourceApp: 'crm',
        payload: {
          'lead_id': lead.id,
          'lead_name': lead.name,
          'product': lead.meta['product'] ?? 'Xizmat',
          'budget': amount,
        },
      ));

      // 2. Mahalliy zaxira yozish
      if (amount > 0) {
        await recordFinanceDealIncome(
          client: lead.name,
          amount: amount,
          note: 'CRM bitim yakunlandi: ${lead.meta['product'] ?? 'Xizmat'}',
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

  void _deleteLead(Entity lead) {
    if (widget.security.currentUser.role != UserRole.director) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Faqat direktor mijoz yozuvini o\'chira oladi.')),
      );
      return;
    }
    widget.service.store.delete(lead.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final leads = _leads;
    final all = widget.service.store.all;
    final newCount = all.where((e) => e.status == 'new').length;
    final contactedCount = all.where((e) => e.status == 'contacted').length;
    final wonCount = all.where((e) => e.status == 'won').length;
    final lostCount = all.where((e) => e.status == 'lost').length;

    return Column(
      children: [
        // Qidirish va Bosqich Filtrlar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Mijoz ismi, telefon yoki mahsulot...',
                  hintStyle: const TextStyle(fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _stageFilter == 'all',
                      label: Text('Barchasi (${all.length})'),
                      onSelected: (_) => setState(() => _stageFilter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _stageFilter == 'new',
                      label: Text('Yangi ($newCount)'),
                      selectedColor: Colors.blue.shade100,
                      onSelected: (_) => setState(() => _stageFilter == 'new'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _stageFilter == 'contacted',
                      label: Text('Muzokara ($contactedCount)'),
                      selectedColor: Colors.orange.shade100,
                      onSelected: (_) => setState(() => _stageFilter == 'contacted'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _stageFilter == 'won',
                      label: Text('Yutildi ($wonCount)'),
                      selectedColor: Colors.green.shade100,
                      onSelected: (_) => setState(() => _stageFilter == 'won'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _stageFilter == 'lost',
                      label: Text('Yo\'qotildi ($lostCount)'),
                      selectedColor: Colors.red.shade100,
                      onSelected: (_) => setState(() => _stageFilter == 'lost'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Plagin: Savdo Voronkasi (Funnel Slot)
        if (widget.pluginManager?.isPluginActive('plugin_crm_funnel') == true)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 16, color: Colors.teal),
                      const SizedBox(width: 6),
                      const Text(
                        'Savdo Voronkasi (Funnel Plagini)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                      ),
                      const Spacer(),
                      Text(
                        'Konversiya: ${all.isNotEmpty ? ((wonCount / all.length) * 100).toInt() : 0}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _FunnelStage(label: 'Yangi', count: newCount, color: Colors.blue)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_right_alt, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(child: _FunnelStage(label: 'Muzokara', count: contactedCount, color: Colors.orange)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_right_alt, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(child: _FunnelStage(label: 'Yutildi', count: wonCount, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),

        // Ro'yxat
        Expanded(
          child: leads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Hech qanday mijoz topilmadi',
                        style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onGoToCreate,
                        icon: const Icon(Icons.add),
                        label: const Text('Yangi mijoz qo\'shish'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: leads.length,
                  itemBuilder: (ctx, idx) {
                    final lead = leads[idx];
                    return _buildLeadCard(lead);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLeadCard(Entity lead) {
    final status = lead.status;
    final phone = lead.meta['phone'] ?? 'Raqam kiritilmagan';
    final product = lead.meta['product'] ?? 'Umumiy';
    final budget = UzbekNlp.parseNumber(lead.meta['budget']);
    final assigned = lead.meta['assigned_to'] ?? 'Menejer';
    final isDirector = widget.security.currentUser.role == UserRole.director;

    Color stageColor;
    String stageText;
    if (status == 'won') {
      stageColor = Colors.green;
      stageText = 'Yutildi ✅';
    } else if (status == 'lost') {
      stageColor = Colors.red;
      stageText = 'Yo\'qotildi ❌';
    } else if (status == 'contacted') {
      stageColor = Colors.orange.shade800;
      stageText = 'Muzokara 💬';
    } else {
      stageColor = Colors.blue;
      stageText = 'Yangi Lid 🆕';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lead.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stageColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: stageColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    stageText,
                    style: TextStyle(color: stageColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                if (isDirector) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                    onPressed: () => _deleteLead(lead),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Metadata Chips
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.phone, size: 14),
                  label: Text('$phone', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Chip(
                  avatar: const Icon(Icons.shopping_bag_outlined, size: 14),
                  label: Text('$product', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Chip(
                  avatar: const Icon(Icons.person, size: 14),
                  label: Text('$assigned', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (budget > 0)
                  Chip(
                    avatar: const Icon(Icons.monetization_on, size: 14, color: Colors.green),
                    label: Text('${budget.toInt()} so\'m', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),

            // Action Buttons
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 'new')
                  FilledButton.icon(
                    onPressed: () => _updateStage(lead, 'contacted'),
                    icon: const Icon(Icons.phone_in_talk, size: 14),
                    label: const Text('Muzokaraga o\'tish', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800, visualDensity: VisualDensity.compact),
                  ),
                if (status == 'contacted') ...[
                  OutlinedButton.icon(
                    onPressed: () => _updateStage(lead, 'lost'),
                    icon: const Icon(Icons.close, size: 14, color: Colors.red),
                    label: const Text('Yo\'qotildi', style: TextStyle(fontSize: 12, color: Colors.red)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _updateStage(lead, 'won'),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Bitim Yutildi (Kassa)', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green, visualDensity: VisualDensity.compact),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 1: MIJOZ QO'SHISH (CORE CREATE FORM)
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
  final _budgetController = TextEditingController(text: '3000000');
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

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'crm_lead_add');
    await tool.handler({
      'name': name,
      'phone': _phoneController.text.trim(),
      'product': _productController.text.trim().isEmpty ? 'Umumiy' : _productController.text.trim(),
      'budget': budget,
      'assigned_to': _selectedAssignee,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" muvaffaqiyatli saqlandi!')),
      );
      _nameController.clear();
      _productController.clear();
      widget.onLeadCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yangi Mijoz / Bitim Qo\'shish',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Mijoz ma\'lumotlarini kiritish va menejerga biriktirish',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Tezkor namunalar
          const Text('Tezkor namunalar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Akfa Korxona (5 mln)'),
                onPressed: () => _addPreset('Akfa Korxona', '+998 90 123 45 67', 'Plastik profil', '5000000'),
              ),
              ActionChip(
                label: const Text('Artel Zavod (12 mln)'),
                onPressed: () => _addPreset('Artel Zavod', '+998 91 987 65 43', 'Elektronika', '12000000'),
              ),
              ActionChip(
                label: const Text('Uzum Market (3.5 mln)'),
                onPressed: () => _addPreset('Uzum Market', '+998 93 555 44 33', 'Yetkazib berish', '3500000'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mijoz nomi
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Mijoz / Korxona nomi *',
              hintText: 'Masalan: OOO Smart Savdo',
              prefixIcon: Icon(Icons.business),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Telefon
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefon raqami',
              hintText: '+998 90 123 45 67',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Mahsulot / Xizmat
          TextField(
            controller: _productController,
            decoration: const InputDecoration(
              labelText: 'Qiziqqan mahsulot yoki xizmat',
              hintText: 'Masalan: Dasturiy ta\'minot o\'rnatish',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Byudjet
          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Taxminiy byudjet summasi (so\'m)',
              hintText: '3000000',
              prefixIcon: Icon(Icons.monetization_on_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Mas'ul menejer
          const Text('Mas\'ul menejer:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _assignees.map((m) {
              final isSel = _selectedAssignee == m;
              return ChoiceChip(
                label: Text(m),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedAssignee = m);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Saqlash tugmasi
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _saveLead,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Mijozni Saqlash', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: PROFIL & SOZLAMALAR (CORE PROFILE & SETTINGS)
// ============================================================================
class CrmProfileTab extends StatefulWidget {
  const CrmProfileTab({
    super.key,
    required this.profileManager,
    required this.pluginManager,
    required this.onProfileChanged,
  });

  final ProfileManager profileManager;
  final PluginManager pluginManager;
  final ValueChanged<UserProfile> onProfileChanged;

  @override
  State<CrmProfileTab> createState() => _CrmProfileTabState();
}

class _CrmProfileTabState extends State<CrmProfileTab> {
  UserProfile get _profile => widget.profileManager.current;

  @override
  Widget build(BuildContext context) {
    final plugins = widget.pluginManager.getAllPlugins();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profil Kartasi
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.teal.shade100,
                    child: Text(
                      _profile.name[0],
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_profile.role.name.toUpperCase()} • ${_profile.department}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_profile.phone}  |  ${_profile.email}',
                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Foydalanuvchini Almashtirish (RBAC)
          const Text(
            'Foydalanuvchi va Rolni Tanlash (RBAC)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Column(
            children: UserProfile.defaultProfiles.map((p) {
              final isCurrent = p.id == _profile.id;
              return Card(
                elevation: 0,
                color: isCurrent ? Colors.teal.shade50 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isCurrent ? Colors.teal.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    p.role == UserRole.director ? Icons.shield : Icons.person,
                    color: isCurrent ? Colors.teal : Colors.grey,
                  ),
                  title: Text(p.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${p.role.name} • ${p.department}'),
                  trailing: isCurrent
                      ? const Icon(Icons.check_circle, color: Colors.teal)
                      : const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                  onTap: () {
                    widget.onProfileChanged(p);
                    setState(() {});
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Tizim & Server Holati
          const Text(
            'Tizim va Microservice Holati',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.dns, color: Colors.green),
                  title: Text('CRM Microservice Server'),
                  subtitle: Text('Port: 8082  |  Holati: Faol (Online)'),
                ),
                Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.hub_outlined, color: Colors.teal),
                  title: Text('Moliya & KPI Integratsiyasi'),
                  subtitle: Text('Portlar: :8081 (KPI), :8083 (Moliya)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Plaginlar Markazi (Microkernel Plugin Registry)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Plaginlar Markazi (Microkernel Engine)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${plugins.where((p) => p.isEnabled).length} ta faol',
                  style: TextStyle(color: Colors.teal.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: plugins.map((plugin) {
                final isConfigurable = plugin.id == 'plugin_ecosystem_bridge' || plugin.id == 'plugin_uzbek_ai';
                return SwitchListTile(
                  dense: true,
                  secondary: Icon(
                    plugin.id == 'plugin_uzbek_ai'
                        ? Icons.auto_awesome
                        : (plugin.id == 'plugin_crm_funnel' ? Icons.filter_alt : (plugin.id == 'plugin_ecosystem_bridge' ? Icons.sync_alt : Icons.extension_outlined)),
                    color: Colors.teal,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(plugin.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      if (isConfigurable)
                        InkWell(
                          onTap: () => _showPluginConfigDialog(context, plugin),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tune, size: 11, color: Colors.teal),
                                SizedBox(width: 3),
                                Text('Sozlash', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(plugin.description, style: const TextStyle(fontSize: 11)),
                  value: plugin.isEnabled,
                  onChanged: (val) async {
                    await widget.pluginManager.togglePlugin(plugin.id, val);
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _showPluginConfigDialog(BuildContext context, EcosystemPlugin plugin) {
    showDialog(
      context: context,
      builder: (ctx) => CrmPluginConfigDialog(
        plugin: plugin,
        pluginManager: widget.pluginManager,
        onSaved: () => setState(() {}),
      ),
    );
  }
}

// ============================================================================
// VORONKA BOSQICHI WIDGETI (FUNNEL STAGE)
// ============================================================================
class _FunnelStage extends StatelessWidget {
  const _FunnelStage({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'crm_lead_add');
    await tool.handler({
      'name': _result!['name'],
      'phone': _result!['phone'],
      'product': _result!['product'],
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
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Bitim & Mijoz Yaratish',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tabiiy tilda yozing, AI mijoz va bitim byudjetini aniqlaydi',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
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
              decoration: InputDecoration(
                hintText: 'Masalan: Akmal bilan 15 mln so\'mlik ERP bo\'yicha yangi bitim och',
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
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
                style: FilledButton.styleFrom(backgroundColor: Colors.purple),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Colors.teal.shade50.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.teal.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified, color: Colors.green, size: 18),
                          const SizedBox(width: 6),
                          const Text('Aniqlangan Bitim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const Divider(height: 16),
                      Text('• Mijoz: ${_result!['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('• Telefon: ${_result!['phone']}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('• Mahsulot/Xizmat: ${_result!['product']}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('• Byudjet: ${(_result!['budget'] as num).toInt()} so\'m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal)),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _confirmAndCreate,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Bitimni Ochish va Saqlash', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                        ),
                      ),
                    ],
                  ),
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

// ============================================================================
// PLAGIN SOZLAMALARI DIALOGI (CRM)
// ============================================================================
class CrmPluginConfigDialog extends StatefulWidget {
  const CrmPluginConfigDialog({
    super.key,
    required this.plugin,
    required this.pluginManager,
    required this.onSaved,
  });

  final EcosystemPlugin plugin;
  final PluginManager pluginManager;
  final VoidCallback onSaved;

  @override
  State<CrmPluginConfigDialog> createState() => _CrmPluginConfigDialogState();
}

class _CrmPluginConfigDialogState extends State<CrmPluginConfigDialog> {
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    final curLimit = widget.plugin.metadata['max_payout_limit'] ?? 3000000;
    _limitController = TextEditingController(text: '$curLimit');
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  void _save() async {
    final val = double.tryParse(_limitController.text.trim()) ?? 3000000.0;
    widget.plugin.metadata['max_payout_limit'] = val;
    await widget.pluginManager.registerPlugin(widget.plugin);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.sync_alt, color: Colors.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.plugin.name, style: const TextStyle(fontSize: 16))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.plugin.description}\n\nMoliya serveri bilan integratsiya (Bitim yutilganda kassa kirimiga avtomat qo\'shish).',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maksimal tushum chegarasi',
              suffixText: 'so\'m',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Bekor qilish'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

