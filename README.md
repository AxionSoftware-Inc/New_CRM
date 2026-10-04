# 🤝 New_CRM: Minimalist CRM, Savdo Voronkasi va Mijozlar Boshqaruvi

> **Business Ecosystem** loyihasining mijozlar bilan ishlash, savdo voronkasi (Funnel) va bitimlarni moliyaga ulash ilovasi.
> GitHub Repozitoriy: [https://github.com/AxionSoftware-Inc/New_CRM.git](https://github.com/AxionSoftware-Inc/New_CRM.git)

---

## 🏛 Arxitektura va Dizayn

Dastur **Mikroyadro (Microkernel)** va **Qat'iy 3-Tab Minimalist** standartida qurilgan:

```
┌─────────────────────────────────────────────────────────────┐
│  APPBAR: [👥 CRM & Mijozlar]   [👤 Vali (Menejer)]   [✨ AI]   [:8082] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Tab 0: Mijozlar]       [Tab 1: Mijoz Qo'shish] [Tab 2: Profil]│
│  ─────────────────      ──────────────────────  ───────────────│
│  • Qidiruv & Bosqichlar • Ism & Telefon         • Foydalanuvchi│
│  • Savdo Voronkasi      • Mahsulot / Xizmat     • Rol Sinash   │
│  • Muzokaraga o'tish    • Byudjet (so'm)        • Server Porti │
│  • Bitim Yutildi (Kassa)• Mas'ul xodim biriktir • Plaginlar    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Plaginlar Tizimi (Microkernel Extensions)

1. **Savdo Voronkasi Plagini (`plugin_crm_funnel`):**
   - Asosiy ekranda lilar oqimini vizual ko'rsatadi:
     `Yangi (Lid) ➔ Muzokara ➔ Bitim Yutildi / Yo'qotildi`
   - Real-vaqt rejimida umumiy konversiya foizini hisoblaydi.
2. **O'zbekcha AI Bitim Ochish (`plugin_uzbek_ai`):**
   - Tabiiy tildagi matndan mijoz, telefon, mahsulot va byudjetni ajratib oladi:
     *"Akmal bilan 15 000 000 so'mlik ERP Tizimi bo'yicha yangi bitim och, tel: +998901234567"*.
3. **Ekotizim Integratsiyasi (`plugin_ecosystem_bridge`):**
   - Bitim holati **"Yutildi" (`won`)** deb belgilanishi bilanoq, shartnoma summasi avtomatik ravishda **Moliya ilovasiga (:8083)** kassa tushumi (kirim) sifatida qayd etiladi.

---

## 🔐 Rollar va RBAC Xavfsizlik Matritsasi

| Harakat | Savdo Xodimi | Sotuv Menejeri | Direktor |
| :--- | :---: | :---: | :---: |
| Mijozlarni ko'rish | Faqat o'ziga biriktirilgan | Barcha mijozlarni | Barcha mijozlarni |
| Bosqichni yangilash (`stage`) | ✅ | ✅ | ✅ |
| Yangi mijoz qo'shish | ✅ | ✅ | ✅ |
| Boshqa xodimga biriktirish | ❌ | ✅ | ✅ |
| Mijoz yozuvini o'chirish | ❌ | ❌ | ✅ |

---

## 🌐 Microservice HTTP API (:8082)

- `GET http://localhost:8082/health` - CRM server holati.
- `GET http://localhost:8082/schema` - Barcha tools va parametrlar.
- `GET http://localhost:8082/export` - Barcha mijozlar JSON eksporti.
- `POST http://localhost:8082/execute` - Funksiya bajarish:
  ```json
  {
    "action": "crm_lead_add",
    "params": {
      "name": "Akmal Fayz",
      "phone": "+998 90 123 45 67",
      "product": "ERP Tizimi",
      "budget": 15000000,
      "assigned_to": "Ali"
    }
  }
  ```

---

## 🚀 O'rnatish va Ishga Tushirish (Mustaqil / Standalone)

```bash
# 1. Paketlarni olish
flutter pub get

# 2. Ishga tushirish
flutter run -d windows

# 3. Testlarni tekshirish (27 ta test)
dart run bin/test_crm.dart
```
