# Tap!Match — App Store Connect Başvuru Bilgileri

Bu doküman, App Store Connect'te "Yeni Uygulama" oluştururken ve sürüm sayfasını doldururken
gireceğin her alanı sırasıyla içerir. Kopyala-yapıştır için hazırdır.

---

## 1. Uygulama Oluşturma (My Apps → + → New App)

| Alan | Değer |
|---|---|
| Platform | iOS |
| Name (Uygulama Adı) | Tap!Match |
| Primary Language | Turkish (veya İngilizce pazar hedefleniyorsa English — sonradan yerelleştirme eklenebilir) |
| Bundle ID | `app.arikan.tapmatch` (Developer hesabında kayıtlı App ID'den seçilir) |
| SKU | `tapmatch-ios-001` (serbest metin, dışarıda görünmez) |
| User Access | Full Access |

> Not: "Tap!Match" adı App Store'da başkası tarafından alınmışsa alternatifler:
> "Tap!Match — Sessiz Eşleşme", "TapMatch: Nomatch".

## 2. Sürüm Bilgileri (1.0.6)

### Promotional Text (170 karakter, sürüm güncellemeden değiştirilebilir)
> Konuşmadan tanışın. İki telefon, on soru, sıfır kelime. Seçimleriniz eşleşirse gerisi size kalmış.

### Description (Türkçe)
> Tap!Match, aynı ortamdaki iki yabancıyı tek kelime etmeden tanıştıran bir oyundur.
>
> İnternet yok, sunucu yok, hesap yok. İki iPhone, Bluetooth ile doğrudan birbirine bağlanır.
>
> NASIL OYNANIR
> • Radar modu: Telefonunu masaya koy, karşındaki de koysun. Telefonlar birbirini bulur.
> • Toplu taşıma modu: Ekranı sola kaydır; çevredeki oyuncular ekranında nokta olarak belirir. Bir noktaya dokun, karşı taraf kabul ederse oyun başlar.
> • Her turda ikinize de aynı iki görsel gösterilir. İçinden geleni seç.
> • 5 kez aynı görseli seçerseniz eşleşirsiniz — ve yalnızca o zaman, isterseniz iletişim bilgilerinizi paylaşırsınız.
> • 5 kez farklı seçerseniz oyun biter. Belki de hiç tanışmamanız gerekiyordu.
>
> NEDEN FARKLI
> • Uygulamada yazı yok, ses yok, profil yok. Yalnızca seçimler.
> • Tamamen çevrimdışı: verileriniz cihazdan çıkmaz, hiçbir sunucuya hiçbir şey gönderilmez.
> • İletişim bilgisi ancak iki taraf da isterse ve yalnızca eşleşme sonrası paylaşılır.
>
> Tap!Match iki iPhone gerektirir. Tek başına oynanamaz — zaten amaç da bu.

### Description (English — İngilizce yerelleştirme eklenecekse)
> Tap!Match introduces two strangers in the same room without a single word.
>
> No internet, no servers, no accounts. Two iPhones connect directly over Bluetooth.
>
> HOW IT WORKS
> • Radar mode: put your phone on the table, so does the other person. The phones find each other.
> • Public transport mode: swipe left; nearby players appear as dots. Tap a dot to send a request.
> • Each round shows both of you the same two images. Pick the one that feels right.
> • Match 5 times and you win — only then, and only if you both want to, you can share contact info.
> • Differ 5 times and the game ends. Maybe you were never meant to meet.
>
> Fully offline. Nothing ever leaves your device. Requires two iPhones — that's the point.

### Keywords (100 karakter, virgülle)
> tanışma,eşleşme,oyun,bluetooth,offline,iki kişilik,sosyal,arkadaş,flört,parti,metro,buzkıran

(İngilizce sürüm için: `icebreaker,match,offline,bluetooth,two player,social,party,meet,strangers,silent`)

### URL'ler
| Alan | Değer |
|---|---|
| Support URL (zorunlu) | GitHub Pages veya basit bir site gerekir. Öneri: `https://kutlu53.github.io/nomatch/` (repo'da Pages açıp store/ dokümanlarını koyabilirsin) |
| Marketing URL (opsiyonel) | boş bırakılabilir |
| Privacy Policy URL (zorunlu) | Aynı Pages sitesinde `store/gizlilik_politikasi.md` içeriğini yayınla, örn. `https://kutlu53.github.io/nomatch/privacy` |

### Sürüm ve Build
| Alan | Değer |
|---|---|
| Version | 1.0.6 |
| Build | Codemagic'ten TestFlight'a düşen 6 numaralı build seçilecek |
| Copyright | © 2026 Mehmet Kutlu Arıkan (Developer hesabındaki tüzel/gerçek kişi adıyla aynı olmalı) |

## 3. Kategori ve Fiyat

| Alan | Değer |
|---|---|
| Primary Category | Games → Casual |
| Secondary Category | Social Networking (opsiyonel ama keşfedilebilirliği artırır) |
| Price | Free (Pricing and Availability sayfasında) |
| Availability | Tüm ülkeler veya önce Türkiye — tercihe bağlı |

## 4. Age Rating (Yaş Derecelendirme Anketi)

Şiddet, kumar, korku vb. sorulara tümüne **Hayır/None**. Kritik sorular:

| Soru | Cevap | Not |
|---|---|---|
| Unrestricted Web Access | No | url_launcher yalnızca WhatsApp/Instagram'a yönlendiriyor, gömülü tarayıcı yok |
| User-Generated Content | No | Kullanıcı içerik üretmiyor, görseller uygulamanın kendi banka'sından |
| Kullanıcılar arası iletişim / kişisel bilgi paylaşımı | **Yes** | Eşleşme sonrası iki taraflı onayla iletişim bilgisi değişimi var. Dürüst cevap bu; muhtemel sonuç **12+ / 13+** derecesi |

> ⚠️ Dikkat: "Yakındaki yabancılarla tanışma + iletişim bilgisi paylaşımı" kombinasyonu,
> inceleme ekibi tarafından sosyal/tanışma uygulaması olarak yorumlanırsa derece 17+'ya
> çekilebilir. Review Notes'ta (aşağıda) paylaşımın yalnızca karşılıklı onayla, oyun sonunda
> ve cihazdan cihaza olduğunu açıkça anlat — bu, dereceyi makul tutmaya yardımcı olur.

## 5. App Privacy (Veri Toplama Beyanı)

En güçlü kozun bu:

| Soru | Cevap |
|---|---|
| Do you or your third-party partners collect data from this app? | **No — Data Not Collected** |

Gerekçe (kendi notun için): backend yok, analytics SDK yok, reklam yok, hesap yok.
Tüm iletişim iki cihaz arasında BLE ile; iletişim bilgisi paylaşımı kullanıcının kendi
eylemi ve veri geliştiriciye hiçbir zaman ulaşmıyor. Etikette "Data Not Collected" rozeti çıkar.

## 6. App Review Information (İnceleme Notları — ÇOK ÖNEMLİ)

| Alan | Değer |
|---|---|
| Sign-in required | No (hesap yok) |
| Contact First/Last Name | Mehmet Kutlu Arıkan |
| Phone | (telefonun) |
| Email | mehmet.kutlu.dio@gmail.com |

### Notes alanına yapıştırılacak metin (İngilizce):
> IMPORTANT — TWO DEVICES REQUIRED:
> Tap!Match is a fully offline, two-player game. The core flow (pairing + gameplay)
> requires TWO physical iPhones with Bluetooth enabled, placed near each other.
> It cannot be experienced on a single device or on a simulator.
>
> Demo video showing the full flow on two devices: [YOUTUBE/DRIVE LİNKİ — mutlaka ekle]
>
> HOW TO TEST: Install on two iPhones, open the app on both, lay both phones flat on
> a table facing each other. They pair automatically (radar mode). Each round, both
> players tap one of two images; 5 matches = win, 5 differences = lose.
>
> DESIGN NOTE: The app intentionally contains no text, no icons and no sound — this is
> the core design concept (nonverbal matching), not missing functionality.
>
> BLUETOOTH BACKGROUND MODES: bluetooth-central and bluetooth-peripheral are used so
> that pairing survives brief app switches; there is no other background activity.
>
> PRIVACY: The app has no server, no account system and collects no data. Contact
> sharing at the end of a game is optional, mutual and transferred directly
> device-to-device over Bluetooth.

> 🎥 Demo videosu hazırla: iki telefonla eşleşme + birkaç tur oyun + kazanma ekranını
> tek çekimde gösteren 1-2 dakikalık video. YouTube'a "unlisted" yükleyip linki
> Notes'a koy. İki cihaz gerektiren uygulamalarda bu, reddedilmeyi önleyen en etkili şey.

## 7. Teknik Ön Koşullar (zaten hazır olanlar)

- [x] `ITSAppUsesNonExemptEncryption = false` — Info.plist'te mevcut, export compliance sorusu sorulmayacak
- [x] Bluetooth/Motion/LocalNetwork izin metinleri Info.plist'te mevcut (TR+EN)
- [x] Yalnızca iPhone (TARGETED_DEVICE_FAMILY = 1) — iPad ekran görüntüsü GEREKMEZ
- [ ] App Icon 1024×1024 (Asset catalog'da mevcut olmalı; App Store Connect ayrıca istemez, build'den alır)
- [ ] Ekran görüntüleri → `store/ekran_goruntusu_plani.md`
- [ ] Gizlilik politikası yayında → `store/gizlilik_politikasi.md` içeriğini bir URL'de barındır

## 8. Gönderim Sırası (özet checklist)

1. Developer hesabında Certificates/Profiles Codemagic'te zaten kurulu (TestFlight çalışıyorsa tamam)
2. App Store Connect → New App (bölüm 1'deki bilgiler)
3. TestFlight'ta 1.0.6 (6) build'ini doğrula
4. Sürüm sayfası: açıklama, keywords, URL'ler, ekran görüntüleri
5. App Privacy: "Data Not Collected"
6. Age Rating anketi
7. Review Notes + demo video linki
8. Pricing: Free
9. "Add for Review" → "Submit to App Review"
