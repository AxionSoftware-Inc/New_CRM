// ignore_for_file: avoid_print
import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:crm_app/crm_service.dart';

void main() async {
  print('================================================================');
  print('   CRM VA SAVDO VORONKASI: TO\'LIQ TEST SINOVI (RBAC & LIFECYCLE)');
  print('================================================================\n');

  final tempDir = Directory.systemTemp.createTempSync('crm_test_');
  final dbPath = '${tempDir.path}/crm_test_data.json';
  int passed = 0;
  int failed = 0;

  void assertTest(String desc, bool condition) {
    if (condition) {
      print('  [PASS] $desc');
      passed++;
    } else {
      print('  [FAIL] $desc');
      failed++;
    }
  }

  try {
    final service = await CrmService.init(dbPath);
    final schema = service.schema;
    final security = SecurityManager();
    final director = SecurityManager.defaultAccounts.firstWhere((a) => a.role == UserRole.director);
    final salesManager = SecurityManager.defaultAccounts.firstWhere((a) => a.role == UserRole.salesManager);
    final sellerAli = SecurityManager.defaultAccounts.firstWhere((a) => a.name.contains('Ali'));

    // 1. Yangi mijoz (Lid) yaratish
    final addTool = schema.tools.firstWhere((t) => t.name == 'crm_add');
    final addRes = await addTool.handler({
      'name': 'Grand Mebel',
      'phone': '+998901234567',
      'company': 'Grand Mebel MCHJ',
      'note': 'Ofis mebellari kerak',
      'assigned_to': 'Ali',
      'deal_amount': 5000000,
    });

    assertTest("1.1. Yangi mijoz muvaffaqiyatli qo'shildi", addRes.success);
    final client1 = service.store.find('Grand Mebel')!;
    assertTest("1.2. Boshlang'ich holat 'lead' (lid)", client1.status == 'lead');
    assertTest("1.3. Mas'ul xodim 'Ali' deb biriktirildi", client1.meta['assigned_to'] == 'Ali');
    assertTest("1.4. Bitim summasi 5 000 000 so'm deb qayd etildi", client1.meta['deal_amount'] == 5000000);

    // 2. Muzokaraga o'tkazish (talk)
    final stageTool = schema.tools.firstWhere((t) => t.name == 'crm_stage');
    final talkRes = await stageTool.handler({
      'name': 'Grand Mebel',
      'stage': 'talk',
    });
    assertTest("2.1. Bosqich 'talk' (muzokara) ga o'tdi", talkRes.success && service.store.find('Grand Mebel')!.status == 'talk');

    // 3. Izoh yozish (crm_note)
    final noteTool = schema.tools.firstWhere((t) => t.name == 'crm_note');
    final noteRes = await noteTool.handler({
      'name': 'Grand Mebel',
      'note': 'Katalog yuborildi, narxlarni ko\'rib chiqmoqda',
    });
    assertTest("3.1. Muloqot izohi muvaffaqiyatli saqlandi", noteRes.success);
    final clientWithNote = service.store.find('Grand Mebel')!;
    assertTest("3.2. Izohlar ro'yxatida kamida 2 ta yozuv bor", (clientWithNote.meta['notes'] as List).length >= 2);

    // 4. Shartnoma/Bitim bosqichiga o'tkazish (deal)
    final dealRes = await stageTool.handler({
      'name': 'Grand Mebel',
      'stage': 'deal',
      'deal_amount': 6000000, // Muzokara yakunida summa oshdi
    });
    assertTest("4.1. Bosqich 'deal' ga o'tdi", dealRes.success && service.store.find('Grand Mebel')!.status == 'deal');
    assertTest("4.2. Yangilangan bitim summasi saqlandi (6 mln)", service.store.find('Grand Mebel')!.meta['deal_amount'] == 6000000);

    // 5. Yutildi (won)
    final wonRes = await stageTool.handler({
      'name': 'Grand Mebel',
      'stage': 'won',
      'reason': 'Shartnoma imzolandi, to\'lov kutilmoqda',
    });
    assertTest("5.1. Bitim muvaffaqiyatli 'won' bo'ldi", wonRes.success && service.store.find('Grand Mebel')!.status == 'won');
    assertTest("5.2. Yutilgan vaqt (won_at) qayd etildi", service.store.find('Grand Mebel')!.meta['won_at'] != null);

    // 6. Uchrashuv va Eslatma sinovi
    final meetTool = schema.tools.firstWhere((t) => t.name == 'crm_meeting');
    final meetRes = await meetTool.handler({
      'name': 'Grand Mebel bilan yetkazib berish shartlari',
      'when': 'ertaga soat 14:00',
      'client': 'Grand Mebel',
    });
    assertTest("6.1. Uchrashuv belgilandi", meetRes.success);

    final meetToggleTool = schema.tools.firstWhere((t) => t.name == 'crm_meeting_toggle');
    final meetId = service.store.find('Grand Mebel bilan yetkazib berish shartlari')!.id;
    final toggleRes = await meetToggleTool.handler({
      'name': meetId,
      'done': true,
    });
    assertTest("6.2. Uchrashuv bajarildi deb belgilandi", toggleRes.success && service.store.find(meetId)!.meta['done'] == true);

    // 7. Reschedule (Surish)
    final reschedTool = schema.tools.firstWhere((t) => t.name == 'crm_reschedule');
    final reschedRes = await reschedTool.handler({
      'name': meetId,
      'when': 'indinga 10:00',
    });
    assertTest("7.1. Uchrashuv vaqti surildi", reschedRes.success && service.store.find(meetId)!.meta['when'] == 'indinga 10:00');

    // 8. Eslatma (crm_remind)
    final remindTool = schema.tools.firstWhere((t) => t.name == 'crm_remind');
    final remRes = await remindTool.handler({
      'name': 'QQS hisobotini yuborish',
      'days': '3 kundan keyin',
    });
    assertTest("8.1. Eslatma qo'yildi", remRes.success);

    // 9. Rad etilgan mijoz (lost)
    await addTool.handler({
      'name': 'Tech Star',
      'phone': '+998939998877',
      'assigned_to': 'Vali',
      'deal_amount': 2000000,
    });
    await stageTool.handler({
      'name': 'Tech Star',
      'stage': 'lost',
      'reason': 'Narx qimmatlik qildi',
    });
    assertTest("9.1. 'Tech Star' rad etildi (lost)", service.store.find('Tech Star')!.status == 'lost');
    assertTest("9.2. Rad etilish sababi saqlandi", service.store.find('Tech Star')!.meta['reason'] == 'Narx qimmatlik qildi');

    // 10. Statistika va Voronka hisob-kitobi (crm_stats)
    final statsTool = schema.tools.firstWhere((t) => t.name == 'crm_stats');
    final statsRes = await statsTool.handler({});
    assertTest("10.1. Statistika muvaffaqiyatli hisoblandi", statsRes.success);
    final statsData = statsRes.data as Map;
    assertTest("10.2. Jami mijozlar soni to'g'ri (2 ta)", statsData['total_customers'] == 2);
    assertTest("10.3. Yutilgan bitimlar soni to'g'ri (1 ta)", statsData['won'] == 1);
    assertTest("10.4. Rad etilganlar soni to'g'ri (1 ta)", statsData['lost'] == 1);
    assertTest("10.5. Jami yutilgan tushum 6 000 000 so'm", statsData['total_won_revenue'] == 6000000);
    assertTest("10.6. Konversiya 50% deb hisoblandi", statsData['conversion_pct'] == 50);

    // 11. RBAC Ruxsatlari
    assertTest("11.1. Direktor mijozni o'chira oladi", security.canDeleteTask(director));
    assertTest("11.2. Sotuv menejeri delegatsiya qila oladi", security.canAssignTask(salesManager));
    assertTest("11.3. Sotuvchi (Ali) o'ziga biriktirilgan mijozni ko'radi", client1.meta['assigned_to'] == sellerAli.name.split(' ').first);

    // 12. O'chirish (crm_delete)
    final delTool = schema.tools.firstWhere((t) => t.name == 'crm_delete');
    final delRes = await delTool.handler({'name': 'Tech Star'});
    assertTest("12.1. Mijoz bazadan muvaffaqiyatli o'chirildi", delRes.success && service.store.find('Tech Star') == null);

  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  print('\n----------------------------------------------------------------');
  print('  NATIJA: Jami ${passed + failed} ta testdan $passed tasi MUVAFFAQITYATLI O\'TDI (Xatolar: $failed)');
  print('================================================================\n');

  if (failed > 0) exit(1);
}
