import 'dart:io';
import 'package:be_core/be_core.dart';

/// CRM va Savdo Voronkasi servisi:
/// Mijozlar bazasi, sotuv voronkasi (Lead -> Talk -> Deal -> Won/Lost),
/// uchrashuvlar, eslatmalar va moliya/KPI bilan integratsiya.
class CrmService {
  CrmService(this.store);
  final StandardStore store;

  static const port = 8082;
  static const stages = ['lead', 'talk', 'deal', 'won', 'lost', 'meeting', 'reminder'];

  static Future<CrmService> init([String? customPath]) async {
    final path = customPath ?? '${Directory.current.path}/crm_data.json';
    final store = await StandardStore.open(path);
    return CrmService(store);
  }

  AppSchema get schema => AppSchema(
        app: 'crm',
        version: '1.1.0',
        description: 'Mijozlar bazasi, bitimlar voronkasi, uchrashuv va eslatmalar',
        port: port,
        tools: [
          // 1. Yangi mijoz qo'shish
          ToolDef(
            name: 'crm_add',
            description: "Yangi mijoz yoki lid qo'shish (stage=lead)",
            params: {
              'name': const ParamDef(type: 'string', description: 'Mijoz ismi yoki tashkilot'),
              'phone': const ParamDef(type: 'string', description: 'Telefon raqami', required: false, defaultValue: ''),
              'company': const ParamDef(type: 'string', description: 'Kompaniya nomi', required: false, defaultValue: ''),
              'note': const ParamDef(type: 'string', description: 'Dastlabki izoh', required: false, defaultValue: ''),
              'assigned_to': const ParamDef(type: 'string', description: 'Mas\'ul xodim (masalan: Sardor)', required: false, defaultValue: 'Sardor'),
              'deal_amount': const ParamDef(type: 'number', description: 'Taxminiy bitim summasi', required: false, defaultValue: 0),
            },
            handler: (p) async {
              final name = '${p['name']}'.trim();
              if (name.isEmpty) return ToolResult.err(error: "Mijoz ismi kiritilmadi.");

              final phone = '${p['phone'] ?? ''}'.trim();
              final company = '${p['company'] ?? ''}'.trim();
              final note = '${p['note'] ?? ''}'.trim();
              final assignedTo = '${p['assigned_to'] ?? 'Sardor'}'.trim();
              final dealAmount = UzbekNlp.parseNumber(p['deal_amount']);

              final entity = store.insert(
                name: name,
                status: 'lead',
                meta: {
                  'phone': phone,
                  'company': company,
                  'assigned_to': assignedTo,
                  'deal_amount': dealAmount,
                  'notes': note.isNotEmpty ? ['${DateTime.now().toIso8601String().substring(0, 16)}: $note'] : [],
                  'last_note': note.isNotEmpty ? note : 'Yangi lid yaratildi',
                  'created_at': DateTime.now().toIso8601String(),
                },
              );
              return ToolResult.ok(
                action: 'crm_add',
                data: entity.toJson(),
                message: "'$name' yangi mijoz sifatida qo'shildi ($phone). Mas'ul: $assignedTo.",
              );
            },
          ),

          // 2. Mijoz bosqichini o'zgartirish (lead -> talk -> deal -> won / lost)
          ToolDef(
            name: 'crm_stage',
            description: "Mijoz holatini o'zgartirish: lead (yangi), talk (muzokara), deal (shartnoma), won (yutildi/sotildi), lost (rad etdi)",
            params: {
              'name': const ParamDef(type: 'string', description: 'Mijoz ismi'),
              'stage': const ParamDef(type: 'string', description: 'lead | talk | deal | won | lost'),
              'deal_amount': const ParamDef(type: 'number', description: 'Bitim summasi', required: false),
              'reason': const ParamDef(type: 'string', description: 'Rad etilish yoki yutish sababi/izohi', required: false),
            },
            handler: (p) async {
              final targetKey = p['name'];
              var stage = '${p['stage']}'.toLowerCase().trim();

              // O'zbekcha so'zlashuvdagi sinonimlarni to'g'irlash
              if (stage.contains('gaplash') || stage.contains('muzokara')) stage = 'talk';
              if (stage.contains('shartnoma') || stage.contains('taklif') || stage.contains('bitim')) stage = 'deal';
              if (stage.contains('yut') || stage.contains('kelish') || stage.contains('oldi') || stage.contains('sotildi') || stage.contains('yop')) stage = 'won';
              if (stage.contains('rad') || stage.contains('yoq') || stage.contains('ketdi') || stage.contains('bekor')) stage = 'lost';

              final existing = store.find(targetKey);
              final dealAmount = p['deal_amount'] != null ? UzbekNlp.parseNumber(p['deal_amount']) : null;
              final reason = p['reason']?.toString().trim();

              if (existing == null) {
                final meta = <String, dynamic>{
                  'notes': ['${DateTime.now().toIso8601String().substring(0, 16)}: Bosqich: $stage'],
                  'last_note': 'Bosqich: $stage',
                  'created_at': DateTime.now().toIso8601String(),
                };
                if (dealAmount != null && dealAmount > 0) meta['deal_amount'] = dealAmount;
                if (reason != null && reason.isNotEmpty) meta['reason'] = reason;

                final entity = store.insert(
                  name: '$targetKey',
                  status: stage,
                  meta: meta,
                );
                return ToolResult.ok(
                  action: 'crm_stage',
                  data: entity.toJson(),
                  message: "'${entity.name}' CRM ga qo'shildi va bosqichi '$stage' qilindi.",
                );
              }

              final metaPatch = <String, dynamic>{
                'updated_at': DateTime.now().toIso8601String(),
              };
              if (dealAmount != null && dealAmount > 0) metaPatch['deal_amount'] = dealAmount;
              if (reason != null && reason.isNotEmpty) metaPatch['reason'] = reason;
              if (stage == 'won') metaPatch['won_at'] = DateTime.now().toIso8601String();
              if (stage == 'lost') metaPatch['lost_at'] = DateTime.now().toIso8601String();

              final updated = store.update(
                existing.id,
                status: stage,
                metaPatch: metaPatch,
              );

              return ToolResult.ok(
                action: 'crm_stage',
                data: updated.toJson(),
                message: "'${updated.name}' bosqichi '$stage' ga o'zgartirildi.",
              );
            },
          ),

          // 3. Bitim summasini belgilash
          ToolDef(
            name: 'crm_deal',
            description: "Mijoz bilan kutilayotgan yoki yakunlangan bitim summasini belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Mijoz ismi'),
              'amount': const ParamDef(type: 'number', description: 'Bitim summasi'),
            },
            handler: (p) async {
              final targetKey = p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' CRM bazasidan topilmadi.");

              final amount = UzbekNlp.parseNumber(p['amount']);
              final updated = store.update(
                existing.id,
                metaPatch: {'deal_amount': amount},
              );

              return ToolResult.ok(
                action: 'crm_deal',
                data: updated.toJson(),
                message: "'${updated.name}' bitim summasi ${amount.toInt()} so'm ga belgilandi.",
              );
            },
          ),

          // 4. Mijozga izoh yozish
          ToolDef(
            name: 'crm_note',
            description: "Mijoz bilan oxirgi suhbat yoki yangilik bo'yicha izoh yozish",
            params: {
              'name': const ParamDef(type: 'string', description: 'Mijoz ismi'),
              'note': const ParamDef(type: 'string', description: 'Izoh matni'),
            },
            handler: (p) async {
              final targetKey = p['name'];
              final note = '${p['note']}'.trim();
              if (note.isEmpty) return ToolResult.err(error: "Izoh matni bo'sh.");

              final existing = store.find(targetKey);
              final timeStamp = DateTime.now().toIso8601String().substring(0, 16);

              if (existing == null) {
                final entity = store.insert(
                  name: '$targetKey',
                  status: 'lead',
                  meta: {
                    'notes': ['$timeStamp: $note'],
                    'last_note': note,
                    'created_at': DateTime.now().toIso8601String(),
                  },
                );
                return ToolResult.ok(
                  action: 'crm_note',
                  data: entity.toJson(),
                  message: "'${entity.name}' CRM ga qo'shildi va izoh yozildi: $note",
                );
              }

              final currentNotes = List<String>.from(existing.meta['notes'] as List? ?? []);
              currentNotes.add('$timeStamp: $note');

              final updated = store.update(
                existing.id,
                metaPatch: {'notes': currentNotes, 'last_note': note},
              );

              return ToolResult.ok(
                action: 'crm_note',
                data: updated.toJson(),
                message: "'${updated.name}' ga izoh saqlandi: $note",
              );
            },
          ),

          // 5. Uchrashuv yoki majlis belgilash
          ToolDef(
            name: 'crm_meeting',
            description: "Uchrashuv, qo'ng'iroq yoki muzokara vaqti belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Uchrashuv mavzusi yoki kim bilan'),
              'when': const ParamDef(type: 'string', description: 'Qachon (masalan bugun 16:00, ertaga 10:00)'),
              'client': const ParamDef(type: 'string', description: 'Mijoz ismi (ixtiyoriy)', required: false),
            },
            handler: (p) async {
              final name = '${p['name']}'.trim();
              final when = '${p['when'] ?? 'bugun'}'.trim();
              final client = p['client']?.toString().trim();

              final entity = store.insert(
                name: name,
                status: 'meeting',
                meta: {
                  'when': when,
                  'date': UzbekNlp.parseDate(when),
                  'client': client,
                  'done': false,
                  'created_at': DateTime.now().toIso8601String(),
                },
              );

              return ToolResult.ok(
                action: 'crm_meeting',
                data: entity.toJson(),
                message: "'$name' uchrashuvi belgilandi: $when.",
              );
            },
          ),

          // 6. Uchrashuv holatini belgilash (bajarildi / o'tkazildi)
          ToolDef(
            name: 'crm_meeting_toggle',
            description: "Uchrashuv o'tkazilganligini belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Uchrashuv nomi yoki ID'),
              'done': const ParamDef(type: 'boolean', description: 'Bajarildimi (true/false)'),
            },
            handler: (p) async {
              final targetKey = p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final done = p['done'] == true || '${p['done']}'.toLowerCase() == 'true';
              final updated = store.update(
                existing.id,
                metaPatch: {'done': done},
              );

              return ToolResult.ok(
                action: 'crm_meeting_toggle',
                data: updated.toJson(),
                message: "'${updated.name}' holati yangilandi (Bajarildi: $done).",
              );
            },
          ),

          // 7. Uchrashuvni boshqa vaqtga surish (reschedule)
          ToolDef(
            name: 'crm_reschedule',
            description: "Mavjud uchrashuv yoki eslatma vaqtini boshqa kunga surish",
            params: {
              'name': const ParamDef(type: 'string', description: 'Uchrashuv nomi yoki shaxs'),
              'when': const ParamDef(type: 'string', description: 'Yangi vaqt (ertaga, indinga, sana)'),
            },
            handler: (p) async {
              final targetKey = p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' nomli uchrashuv yoki eslatma topilmadi.");

              final when = '${p['when']}'.trim();
              final updated = store.update(
                existing.id,
                metaPatch: {'when': when, 'date': UzbekNlp.parseDate(when)},
              );

              return ToolResult.ok(
                action: 'crm_reschedule',
                data: updated.toJson(),
                message: "'${updated.name}' vaqti '$when' ga surildi.",
              );
            },
          ),

          // 8. Eslatma qo'yish
          ToolDef(
            name: 'crm_remind',
            description: "Eslatma qo'yish (masalan: 3 kundan keyin qo'ng'iroq qilish)",
            params: {
              'name': const ParamDef(type: 'string', description: 'Eslatma matni'),
              'days': const ParamDef(type: 'string', description: 'Necha kundan keyin yoki sana'),
            },
            handler: (p) async {
              final name = '${p['name']}'.trim();
              final date = UzbekNlp.parseDate(p['days']);

              final entity = store.insert(
                name: name,
                status: 'reminder',
                meta: {
                  'remind_date': date,
                  'done': false,
                  'created_at': DateTime.now().toIso8601String(),
                },
              );

              return ToolResult.ok(
                action: 'crm_remind',
                data: entity.toJson(),
                message: "Eslatma saqlandi: '$name' ($date).",
              );
            },
          ),

          // 9. Ro'yxatni ko'rish (filtrlar bilan)
          ToolDef(
            name: 'crm_list',
            description: "Mijozlar, uchrashuvlar va eslatmalar ro'yxati",
            params: {
              'stage': const ParamDef(type: 'string', description: 'lead|talk|deal|won|lost|meeting|reminder bo\'yicha filtr', required: false),
              'assigned_to': const ParamDef(type: 'string', description: 'Mas\'ul xodim bo\'yicha filtr', required: false),
            },
            handler: (p) async {
              final filterStage = p['stage'] as String?;
              final assignedTo = p['assigned_to']?.toString().toLowerCase().trim();

              var list = store.filter(status: filterStage);
              if (assignedTo != null && assignedTo.isNotEmpty) {
                list = list.where((e) {
                  final resp = '${e.meta['assigned_to'] ?? ''}'.toLowerCase();
                  return resp.contains(assignedTo);
                }).toList();
              }

              return ToolResult.ok(
                action: 'crm_list',
                data: list.map((e) => e.toJson()).toList(),
                message: "Jami ${list.length} ta yozuv topildi.",
              );
            },
          ),

          // 10. Voronka va konversiya statistikasi
          ToolDef(
            name: 'crm_stats',
            description: "CRM voronkasi tahlili: lidlar, muzokaralar, bitimlar, tushum va konversiya",
            params: {},
            handler: (p) async {
              final allCustomers = store.all.where((e) => e.status != 'meeting' && e.status != 'reminder').toList();
              final leads = allCustomers.where((e) => e.status == 'lead').length;
              final talks = allCustomers.where((e) => e.status == 'talk').length;
              final deals = allCustomers.where((e) => e.status == 'deal').length;
              final wonList = allCustomers.where((e) => e.status == 'won').toList();
              final lostList = allCustomers.where((e) => e.status == 'lost').toList();

              num totalWonRevenue = 0;
              for (final w in wonList) {
                totalWonRevenue += UzbekNlp.parseNumber(w.meta['deal_amount']);
              }

              num activePipelineValue = 0;
              for (final c in allCustomers.where((e) => e.status == 'talk' || e.status == 'deal')) {
                activePipelineValue += UzbekNlp.parseNumber(c.meta['deal_amount']);
              }

              final total = allCustomers.length;
              final conv = total > 0 ? ((wonList.length / total) * 100).round() : 0;

              return ToolResult.ok(
                action: 'crm_stats',
                data: {
                  'total_customers': total,
                  'lead': leads,
                  'talk': talks,
                  'deal': deals,
                  'won': wonList.length,
                  'lost': lostList.length,
                  'conversion_pct': conv,
                  'total_won_revenue': totalWonRevenue,
                  'active_pipeline_value': activePipelineValue,
                },
                message: "CRM Statistikasi: Jami mijoz: $total, Yutildi: ${wonList.length} (${totalWonRevenue.toInt()} so'm), Konversiya: $conv%.",
              );
            },
          ),

          // 11. O'chirish
          ToolDef(
            name: 'crm_delete',
            description: "Mijoz, uchrashuv yoki eslatmani o'chirish",
            params: {
              'name': const ParamDef(type: 'string', description: 'O\'chiriladigan yozuv nomi yoki ID'),
            },
            handler: (p) async {
              final targetKey = p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' CRM bazasidan topilmadi, o'chirib bo'lmadi.");

              final removed = store.delete(existing.id);
              return ToolResult.ok(
                action: 'crm_delete',
                data: removed.toJson(),
                message: "'${removed.name}' CRM bazasidan o'chirildi.",
              );
            },
          ),
        ],
      );
}
