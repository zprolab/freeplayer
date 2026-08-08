# FreePlayer (Android)

مشغّل موسيقى محلي. دون اتصال بالشبكة، دون تسجيل دخول، دون جمع أي بيانات. موسيقاك تبقى على جهازك، بهيكل مجلداتك الخاص.

> تتوفر نسخة لنظام macOS (SwiftUI) في فرع `Swift`؛ النسخة القديمة للويب في فرع `master`.

## الصيغ المدعومة

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (حسب مُفكِّكات النظام)

## المزايا

- **الاستيراد والمشاركة**: استيراد المجلدات عبر منتقي الملفات بالنظام؛ الصوت المُشارك من تطبيقات أخرى (WeChat، مديرو الملفات…) يُستورد بلمسة واحدة عبر «فتح باستخدام FreePlayer»
- **المكتبة**: استخراج تلقائي للبيانات الوصفية (العنوان، الفنان، الألبوم، السنة، النوع، رقم المقطع، معدل البت، معدل العينة، القنوات)، مخزَّنة بهيكل فنان/ألبوم مع أغلفة مضمّنة
- **إحصاءات الاستماع**: كل تشغيل يُسجَّل (البداية/النهاية، المدة، النسبة) — إجمالي الوقت، عدد التشغيلات، أفضل 10 مقاطع/فنانين، إحصاءات يومية لآخر 30 يومًا
- **قوائم التشغيل**: إنشاء/إعادة تسمية/حذف، إضافة فردية أو دفعة، تحرير القائمة
- **كلمات LRC**: كشف تلقائي أو ربط يدوي لملفات .lrc؛ ترميزات UTF-8 ← GB18030 ← Shift_JIS
- **ReplayGain**: ضبط تلقائي لمستوى الصوت
- **المرئيات**: راسم ذبذبات + طيف + مخطط طيفي شلالي
- **الوضع الغامر**: تشغيل بملء الشاشة دون مشتتات
- **مفاتيح الوسائط / الإشعارات**: تحكم عبر إشعار الخدمة الأمامية؛ يعمل على شاشة القفل ومع سماعات Bluetooth

## البناء

يتطلب Android SDK (compileSdk 37، minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # APK تجريبي
./gradlew :app:assembleRelease   # APK للإصدار (يتطلب إعداد التوقيع)
./gradlew :app:testDebugUnitTest # اختبارات الوحدة
```

توقيع الإصدار: ضع `freeplayer-release.jks` و`keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) داخل `Android/`؛ الملف مستثنى من git ولا يُرفع أبدًا.

## قاعدة البيانات

SQLite، في دليل بيانات التطبيق الخاص:

- tracks — المقاطع (replaygain، lrc_path، …)
- play_history — سجل التشغيل
- playlists / playlist_tracks — قوائم التشغيل ومقاطعها
- settings — إعدادات مفتاح-قيمة

## الترخيص

GPL v3 — انظر LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
