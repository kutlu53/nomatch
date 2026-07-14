# Tap!Match — App Store Ekran Görüntüsü Planı

Uygulama yalnızca iPhone ve yalnızca dikey (portrait) olduğu için işin kolay tarafı:
**tek boyut seti yeterli, iPad gerekmez.**

## Teknik Gereksinimler

| Özellik | Değer |
|---|---|
| Zorunlu boyut | 6.9" — **1320 × 2868 px** (iPhone 16/17 Pro Max) veya 1290 × 2796 (15 Pro Max) |
| Alternatif kabul edilen | 6.5" — 1284 × 2778 veya 1242 × 2688 (App Store Connect küçük ekranlara bunu ölçekler) |
| Adet | En az 3, en fazla 10 (öneri: 5-6) |
| Format | PNG veya JPG, alfa kanalsız |
| Yön | Dikey |

**En pratik yol:** TestFlight build'ini bir Pro Max cihazda aç, ekran görüntüsü al
(yan tuş + ses açma) — çıkan PNG doğru çözünürlüktedir, olduğu gibi yüklenebilir.
Pro Max cihaz yoksa Xcode simülatöründe (iPhone 16 Pro Max) da alınabilir; ancak
BLE simülatörde çalışmadığı için eşleşme/oyun ekranları için iki gerçek cihaz gerekir.

## Çekilecek Sahneler (sıralama = mağazadaki sıra)

Kural: ilk 2-3 görsel, mağaza sayfasında kaydırmadan görünür — en güçlü sahneler öne.

| # | Sahne | Nasıl yakalanır | Neyi anlatır |
|---|---|---|---|
| 1 | **Oyun turu** — iki görsel ekranda, biri seçili (mor vurgu) | İki cihazla oyun başlat, seçim yaptıktan hemen sonra çek | Oyunun özü: iki görsel, bir seçim |
| 2 | **Radar modu** — halkalar + eşleşme anı | İki telefon masada; eşleşme animasyonu sırasında çek | "Telefonu koy, eşleş" sihri |
| 3 | **Toplu taşıma modu** — ekranda 2-3 dot | İkinci cihaz (mümkünse üçüncü) yakında açıkken çek | Kalabalıkta keşif |
| 4 | **Kazanma / secret link anı** | 5 benzerlik tamamlanınca geçiş sırasında çek | Ödül duygusu |
| 5 | **Paylaşım ekranı** | Kazanma sonrası paylaşım ekranında çek | Gerçek dünyaya köprü |
| 6 | (ops.) **Başlangıç ekranı** — üçgen buton | Uygulama açılışında çek | Sade kimlik |

> Not: Uygulamada metin olmadığı için ham ekran görüntüleri tek başına az bilgi verir.
> Bu yüzden pazarlama çerçevesi (aşağıda) bu uygulamada ortalamadan daha önemli.

## Pazarlama Çerçevesi (önerilen)

App Store, ekran görüntüsü alanında çerçeveli/başlıklı kompozisyonlara izin verir.
Ham görüntülerin üstüne kısa başlık + cihaz çerçevesi eklemek dönüşümü ciddi artırır:

| # | Başlık önerisi (TR) | (EN) |
|---|---|---|
| 1 | Konuşma. Sadece seç. | Don't talk. Just tap. |
| 2 | Telefonu koy, eşleş. | Put the phone down, get matched. |
| 3 | Metroda, kafede, her yerde. | On the metro, at the café, anywhere. |
| 4 | 5 benzerlik = eşleşme. | Match 5 times, win. |
| 5 | Tanışmak isterseniz — ikiniz de. | Share contact — only if you both want. |
| 6 | İnternet yok. Sunucu yok. İz yok. | No internet. No servers. No trace. |

Stil: Ink Plum (#191423) arka plan, uygulamanın mor vurgu rengi, başlık üstte,
cihaz çerçevesi altta hafif taşırılmış — mağaza sayfası uygulamanın kendisi gibi görünür.

## İş Bölümü

1. **Sen:** TestFlight build'iyle iki cihazda yukarıdaki 5-6 sahnenin ham ekran
   görüntüsünü al (Pro Max varsa cihazdan; yoksa normal iPhone'dan al, bana gönder).
2. **Ben:** Ham görüntüleri alınca 1320×2868 pazarlama çerçevelerine yerleştirip
   (arka plan + başlık + cihaz çerçevesi) yüklemeye hazır PNG'leri üretirim.
   Normal boyut iPhone görüntüsü gelirse Pro Max tuvaline ben ölçeklerim.

## App Preview (opsiyonel video)

15-30 sn'lik dikey video eklenebilir (1080×1920 kabul edilir). İki telefonun masada
eşleşip birkaç tur oynandığı tek çekim, sessiz + altyazısız haliyle bile çok etkili
olur. App Review demo videosundan ayrıdır ama aynı çekim malzemesi ikisine de yarar.
