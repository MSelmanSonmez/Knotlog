# Knotlog — kullanım kılavuzu

Knotlog'u kurdun, kasan (vault) oluştu. Bu kılavuz ondan sonrasını anlatır: ne
kendiliğinden oluyor, neyi sen yapıyorsun, hangi soruya hangi komut cevap
veriyor. Kurulumun kendisi için [README](../README.md) dosyasına bak.

> **Eski adı Quipu.** Knotlog, Quipu'nun yeni adıdır; eski `quipu` komutu kaldırıldı. Eski adla oluşturulmuş bir kasan varsa değişiklikleri görmek için `knotlog migrate`, yazmak için `knotlog migrate --apply` çalıştır; bu komut eski `quipu` hook komutlarını da `knotlog` olarak yeniden yazar. Elle düzenlediğin bir köprü bloğu yenilenmez (yalnız işaretleri çevrilir) ve uyarı alırsın.

Henüz kurmadıysan tek satırlık yol şu:

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

Betik doğrulanmış sürümü indirir ve `knotlog install`'a devreder; klonlayarak
kurulumu ve Windows yolunu [README](../README.md) anlatıyor.
Kurulum sihirbazında Üslup adımı (ton, süs, klasör adları) var; sonradan `knotlog tone` ve `knotlog flair` ile değişir. PATH'te daha önce gelen eski bir `knotlog` varsa kurulum özeti ve `knotlog doctor` uyarır, çünkü kancalar onu çalıştırır.

## 1. Knotlog senin için ne yapıyor

Knotlog, kodlama ajanının ne yaptığını Markdown olarak tek bir klasöre — kasaya —
yazar. Bir Claude Code oturumunun etrafında üç şey olur:

- **Sen çalışırken**, ajanın okuduğu ya da yazdığı her dosya
  `.knotlog/activity.log` dosyasına tek satır olarak eklenir: zaman damgası,
  olay, araç, yol.
- **Oturum kapanınca**, o satırlar Oturumlar klasörü altında tarihli bir nota
  dönüşür ve arama indeksi tazelenir.
- **Bir sonraki oturum açılınca**, Knotlog son etkinliği, açık konuları ve bir
  kimlik satırını modelin bağlamına geri basar — ajan geçen sefer ne olduğunu
  bilerek açılır. İlk satır her zaman güncel tarih, saat ve gün adıdır
  (`şimdi: 2026-09-02 20:15 Çarşamba`) — bu olmadan hafıza yazan model saati
  tahmin etmek zorunda kalır ve tahminler sapar.

Veritabanı yok, ağ isteği yok. Her dosya okuyabileceğin, düzenleyebileceğin ve
git'e koyabileceğin Markdown. Knotlog yalnızca ekler; senin yazdığın metni asla
yeniden yazmaz.

## 2. Günlük döngü

İlk kafa karıştıran nokta şu: döngünün bir kısmı kendi kendine işliyor, bir
kısmı sana ait. Ayrım şöyle.

**Kendiliğinden çalışan** (Claude Code adaptörü,
`<kasa>/.claude/settings.json` içinde kurulu):

| Ne zaman | Ne çalışıyor | Sonuç |
|---|---|---|
| Oturum açılınca | `knotlog remember && knotlog context --json SessionStart` | bekleyen log satırları oturum notuna dönüşür, yakın hafıza enjekte edilir |
| Gönderdiğin her istem | `knotlog context --json UserPromptSubmit` | yeterince yeni log satırı birikince modele "hafızanı yaz" hatırlatması gider |
| `Edit`/`Write`/`NotebookEdit`/`Read` sonrası | `knotlog capture` | `activity.log`'a sessizce bir satır eklenir |
| Oturum kapanınca | `knotlog remember && knotlog index` | oturum notu yazılır, indeks tazelenir |

Bunun çalışması için iki koşul var: `knotlog` `PATH`'te olmalı ve Claude Code hook
yapılandırmasını yalnızca açılışta okuduğu için **`settings.json` her
değiştiğinde yeniden başlatılmalı**.

**Senin yapacakların:**

1. Çalışırken notlarını kasa klasörlerine yaz. Knotlog oraya koyduğunu indeksler;
   senin yerine not uydurmaz.
2. Oturum sonunda o günün oturum notundaki yansıma bloğunu doldur. İskelet üç
   başlıkla hazır duruyor. Ajan da doldurabilir — `SessionStart` bağlamı bunu
   ondan ister — ama doldurup doldurmadığını kimse denetlemiyor.
3. Konular dosyasını (`Konular.md`) güncel tut: ne açık, ne kapandı.
4. Önceki bir oturumdan bir şey lazım olduğunda baştan anlatmak yerine
   `knotlog search` çalıştır.

Mekanik defteri Knotlog tutar. Anlamı sen ve model yazar.

## 3. Klasörler ne işe yarar

`init` on klasör oluşturur. Aşağıdaki adlar Türkçe yerleşimden; İngilizce kasada
İngilizce, `--plain` ile ASCII adlar gelir. Hiçbiri zorunlu değil — bunlar bir
alışkanlık, şema değil.

| Klasör | Buraya ne zaman yazarsın |
|---|---|
| `📥 Gelen Kutusu` | bir düşünce geldi ve nereye ait olduğuna şimdi karar vermek istemiyorsun |
| `🗑️ Çöp Kutusu` | gelen kutusunun içine ham malzeme dökerken — yapıştırmalar, parçalar, dökümler |
| `🎯 Komuta Merkezi` | panele ait olan şeyler: günün odağı, giriş bağlantıları |
| `🗂️ Projeler` | not tek bir aktif işe dair — proje başına bir alt klasör |
| `🧠 Bilgi` | aylar sonra yine lazım olacak, projeden bağımsız duran şeyler |
| `🛠️ Aletler` | bir araç, betik ya da yeniden kullanılacak bir parça |
| `📆 Oturumlar` | neredeyse hiç elle — buraya `knotlog remember` yazar, gün başına bir dosya |
| `🔮 Asistan` | asistanın personası ve taşıdığı kimlik notları |
| `📦 Arşiv` | iş bitti ya da donduruldu, gözünün önünden çekilsin |
| `📋 Şablonlar` | yerinde düzenleme yok — `note.md`, `project.md`, `session.md` dosyalarını kopyalayıp çıkar |

Şablonlar klasörü bu üç iskeletle geliyor ve **arama indeksine dahil değil**:
onlar kopyalanacak biçimler, bulunacak içerik değil. Üç notu ve üç şablonu olan
bir kasada indekse notlar girer, şablonlar girmez.

## 4. Elinle yazacağın komutlar

Aşağıdakilerin hepsi kasanın içinde çalışır (herhangi bir alt klasör de olur —
Knotlog `.knotlog/` dizinini bulana kadar yukarı yürür).

**`knotlog search <terimler>`** — bir notu bul.

```
$ knotlog search "acik kaynak"
2.524	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

**`knotlog links <yol>`** — bir notun neye bağlandığını gör. Kasaya göreli yolu
ver.

```
$ knotlog links "🧠 Bilgi/opencv.md"
giden bağlantılar
gelen bağlantılar
🧠 Bilgi/dpi.md
```

Giden bağlantılar o notun içine yazılmış `[[wikilink]]`'ler; gelenler ise onu
işaret eden notlar. Bağlantı hedefleri katlanmadan, birebir eşleşmeyle çözülür —
`[[opencv]]` (dosya adı kökü) ya da kasaya göreli tam yol yaz.

**`knotlog digest`** — bir günün etkinliğini, oturum işaretini ilerletmeden
özetle. `--dry-run` yazmadan basar, `--date YYYY-MM-DD` günü seçer, dosya çöp
kutusu klasörüne düşer.

```
$ knotlog digest --dry-run
---
Etkinlik özeti: 2026-08-30
type: digest
status: generated
---

Aralık: 2026-08-30T23:05 → 2026-08-30T23:05 (2 olay)
Araçlar: Edit 1, Write 1
Dokunulan dosyalar (en çok 10):
- 🧠 Bilgi/dpi.md (1)
- 🧠 Bilgi/opencv.md (1)
```

**`knotlog doctor`** — sağlık denetimi. 7. bölüme bak.

**`knotlog import DOSYA`** — kaydedilmiş bir sohbet dışa aktarımını (Claude
döküm dosyası, ChatGPT dışa aktarımı ya da `role`/`content` içeren JSONL) oturum
notuna çevirir.

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
yazıldı: 📆 Oturumlar/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <ad> --proje <Proje>`** — plan notunu ait olduğu yerde açar:
`<Projeler>/<Proje>/<Planlar>/<ad>.md`, yerelleştirilmiş frontmatter'lı
şablondan doğar, `$EDITOR` tanımlıysa içinde açılır. Planlar hafızadır —
kasada durmaları sonraki oturumun devralmasını sağlayan şeydir; bu yüzden
olmayan proje klasörü hata verir, asla otomatik açılmaz, olan plan da asla
üzerine yazılmaz. Proje klasörünün içindeyken çalıştırırsan `--proje` kendi
kendine çözülür.

```
$ knotlog plan yol-haritasi --proje Knotlog
yazıldı: 🗂️ Projeler/Knotlog/Planlar/yol-haritasi.md
```

**`knotlog tone [--list|<slug>]`** — üslup presetini gösterir ya da ayarlar.
Argümansız çağrı hangi kaynağın etkin olduğunu ve nedenini basar (bir preset
slug'ı, ya da companion.md'nin kendi Üslup bölümü, ya da hiçbiri); `--list`
dokuz hazır seti listeler (Varsayılan, Profesyonel, Dostane, İçten, Sıra
Dışı, Etkili, Sivri Dilli, Öğretici, Kaomoji) ve etkin olanı işaretler; `<slug>`
`.knotlog/config`'e `tone=<slug>` yazar — companion.md'ye asla dokunmaz.

```
$ knotlog tone --list
Üslup setleri:
  varsayilan   Varsayılan — Hazır ayarlı üslup ve konuşma tonu
  profesyonel  Profesyonel — Özenli ve net
  ...
* etkili       Etkili — Kısa, öz ve net
  ...
$ knotlog tone
etkin üslup: Etkili (preset: etkili)
```

**`knotlog index`** — indeksi elle tazele. Hook'lar bunu oturum sonunda yapar;
oturum dışında not eklediysen sen çalıştır. `--full` her şeyi baştan kurar.

```
$ knotlog index
# indekslendi 5 (yeniden 4, bayat 1, düştü 0)
```

**`knotlog remember`** — oturum notunu oturum sonunu beklemeden şimdi yaz.
`--git` eklersen ardından kasayı commit eder; eklemezsen Knotlog asla commit
atmaz.

```
$ knotlog remember
yazıldı: 📆 Oturumlar/2026-08-30.md
```

## 5. Kendi hafızanda arama

`search` sorguyu katlar, indeksi BM25 ile puanlar ve en iyi satırları TAB ile
ayrılmış sütunlar hâlinde basar: puan, yol, başlık, etiketler. Varsayılan on
satır.

- `--limit N` — kaç satır.
- `--paths` — yalnızca yol sütunu, satır başına bir tane:
  `knotlog search dpi --paths`.
- `--brief` — notun yaklaşık 120 baytlık bir künyesini ek sütun olarak verir. On
  notu açmak yerine hangi ikisini açacağına karar vermek için kullan.
  `--paths` ile birlikte kullanılamaz.
- `--tag ui` / `--status aktif` — front matter'ı eşleşmeyen notu tamamen eler.
  Bunlar sıralama ipucu değil, filtre; birlikte verilirse VE olarak çalışır.

Puanlar mutlak değil, kasana göreli — küçük bir kasada filtrelenmiş bir eşleşme
sıfırın altında puan alıp yine de aradığın not olabilir.

**Katlama ve Türkçe için neden önemli.** İndekslemeden ve aramadan önce metin,
`.knotlog/config` içinde `fold=` olarak kayıtlı bir katlama profilinden geçer.
Türkçe kasa `fold=tr` alır: `İ ı ğ ş ç ö ü` ASCII karşılıklarına iner, böylece
sorgu ile not ortada buluşur.

```
$ knotlog search "acik kaynak"
2.524	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.524	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

Her iki yazım da notu buluyor. `default` profili — İngilizce kasanın aldığı
profil — ASCII büyük/küçük harf dışında hiçbir şeyi katlamaz; orada `acik`,
`açık` yazan notu bulmaz. İngilizce yerleşimli bir kasada Türkçe yazıyorsan
`.knotlog/config` içine `fold=tr` yaz ve bir kez `knotlog index --full` çalıştır;
indeksin yeni profille yeniden kurulması gerekiyor.

Katlama bilerek kayıplı: `açık` ile `acık` aynı anahtara düşer. Bilinen bir
boşluk: `--tag` kendi argümanını katlar ama front matter'daki ham metinle
karşılaştırır — yani `--tag istanbul`, `İstanbul` yazılmış bir etiketi bulmaz.

## 6. Konular (Threads) ve oturum notları

Oturumlar arasında hikâyeyi dört dosya taşır.

**Günün oturum notu** (`📆 Oturumlar/YYYY-AA-GG.md`) `remember` tarafından
yazılır. Üst kısmı mekaniktir — zaman aralığı, araç sayıları, dokunulan
dosyalar. Altında Knotlog'un bir kez eklediği ve bir daha asla dokunmadığı bir
iskelet durur:

```
<!-- knotlog:reflect:start -->
### Bu oturumda ne değişti?

### İş nerede yapıldı?

### Dokunulan ya da sürdürülen konular

<!-- knotlog:reflect:end -->
```

Asıl iş bunu doldurmak. Aynı gün ikinci kez `remember` çalışması oraya
yazılanı ezmez. Blok boş olduğu sürece `SessionStart` modelden dosyayı adıyla
söyleyerek doldurmasını ister; dünkü blok boş bırakıldıysa bir sonraki oturumda
bu bir kez söylenir ve uyarı düşer.

**`Konular.md`** (İngilizce kasada `Threads.md`) kasanın kökünde durur ve bir günü aşan hikâye hatlarını
`### Aktif konular` / `### Kapanmış konular` başlıkları altında tutar. `knotlog
context` bu dosyayı her oturuma geri besler — bu yüzden kasadaki en yüksek
kaldıraçlı dosya odur, ve çürümeye bırakması en ucuz dosya da odur. Kısa tut;
kapanan bir konu yukarıda durmasın, aşağı insin.

`knotlog note --thread "<metin>"` aktif bölüme satır ekler, ama yalnız dosya
context bütçesine sığdığı sürece: `context`'in bölümü kırpmasına yol açacak satır
reddedilir (çıkış kodu 3, hiçbir şey yazılmaz) ve mesaj kaç bayt yer açılması
gerektiğini ve nasıl açılacağını söyler (`knotlog compact --apply`, `knotlog
archive` ya da daha büyük bir `ctx_max`). Geçmiş bir oturumda olan şey buraya
girmez; oturum notlarında kalır, `knotlog search` onu bulur.

`note`'un iki biçimi de sır gibi görünen metni (API anahtarı, token, özel
anahtar) çıkış kodu 4 ile reddeder. Her satırı yazılmadan önce görmek
istersen `.knotlog/config`'e `write_approval=on` yaz: notlar `knotlog pending
--approve N` (ya da `--reject N`) çalıştırana kadar `.knotlog/pending`'de
bekler; ajana verilmiş bir emir gibi okunan satır ("bundan sonra … yapmalısın")
reddedilir, "yarın" geçen satır tarih verebilesin diye bekletilir.

### Kurallar dosyası

`init`, kasanın köküne **`Kurallar.md`** (İngilizce kasada `Rules.md`)
tohumlar — kasada çalışan her ajanın miras aldığı davranış sözleşmesi.
Sevkedilen varsayılan, Knotlog'un pazarlığa kapalı saydığı dört blok taşır:

- **Onay kapıları** — para hareketi, dışarı çıkan mesaj, silme ve gizli bilgi
  onaysız geçilmez; bir evet, tek oturumdaki tek işe yarar.
- **Sıfır seviye protokoller** — on bir temel çalışma alışkanlığı (sözleşme
  kapsamı, başlamadan önce bitiş tanımı, kontrol çıktısını dosyaya yazmak,
  "bitti" demeden önce raporlanacak üç şey, mantıklı adım başına tek commit,
  oturum sonunda üç satır ve daha fazlası), her birinin altında var oluş nedeni.
- **Makbuz kuralı** — commit, güncellenen dosya, diske yazılan çıktı makbuzdur;
  "yaptım" değildir. İz yoksa iş yoktur.
- **Kayıt disiplini** — yeni kayıt eskiyi geçersiz kılıyorsa eskisini emekliye
  ayır: eski adı kasada ara, kapat ya da güncelle; aynı konuda iki canlı kayıt
  bırakma.

Dosyayı dilediğin gibi düzenle — senindir; Knotlog asla ezmaz (diğer dildeki adıyla
duran mevcut dosya dahi kazanır). `knotlog context` dosyanın başlıklarını her
oturuma, konular bölümünden sonra enjekte eder; sıkıştırılmış bir `ctx_max` bu
bölümü bütün halinde düşürür, asla konular bloğunu kesmeden önce. `doctor` ise
sevkedilen şablonları ürün dosyaları arasında kontrol eder. Tohumu elle
düzenleyene dek o, elle yazılmış bir hafıza dosyası sayılmaz — yani taze kasa
`doctor`'dan temiz çıkar; içine ilk satırı yazdığın anda 7. bölümde anlatılan
zorunlu anlatı setine katılır.

Köprü (`AGENTS.md`/`CLAUDE.md`) oturumların kötü bittiği yerde hikâyeyi ayakta
tutan kontrol noktası protokolünü taşır: kaydı iş bittiği anda yaz, oturum
sonunu bekleme; iş yarıda kaldıysa nerede kalındığını ve sıradaki adımı yaz;
kullanıcı ayrılacağını ima ettiğinde kapanmadan önce kaydı tamamla.

Bu dosyaların hiçbirini Knotlog asla yeniden yazmaz. Onun tarafından dördü de
salt eklemelidir.

### Gerçekler dosyası

`init`, kasanın köküne **`Gerçekler.md`** (İngilizce kasada `Facts.md`)
tohumlar — kalıcı gerçekler katmanı, hiçbir dış hafıza servisi olmadan
tutulur. Kural **tek satır, tek gerçek**: her madde satırı üç etiketten
biriyle açılır — `Karar:` (verilmiş seçim ve gerekçesi, değişene dek geçerli),
`Tercih:` (nasıl çalışmayı seversin), `Konvansiyon:` (bu kasada işlerin
yürüyüşü). Giriş barajı: bir satır aylar sonra da hem doğru hem işe yarar
olacaksa girer — **kimlik geçer, haber geçemez**; bayatlayacak bilgi
`Konular.md`'ye ya da oturum notlarına gider.

Dosyayı dilediğin gibi düzenle — senindir; Knotlog asla ezmaz (diğer dildeki
adıyla duran mevcut dosya dahi kazanır). `knotlog context` gerçek satırlarını
her oturuma, kurallar bölümünün ardından enjekte eder — aynı `ctx_max`
sözleşmesiyle: sıkışan bütçe bölümü bütün halinde düşürür, konular bloğunu
asla kesmez. Dokunulmamış tohum iskeletin kendisidir, kayıt değil — ilk
satırını yazana dek context ondan sessiz kalır. `doctor`, dosya varken
gerçek satırı sayısını söyleyen tek bir `ok` satırı basar; katmandan önceki
kasalarda sessizdir.

## 7. Bir şey ters gidince

`knotlog doctor` her alan için bir bölüm ve sonda bir özet satırı basar. Yalnızca
uyarı varsa 0, bir şey başarısızsa 1 ile çıkar.

```
özet: 151 ok, 3 uyarı, 0 hata
```

**Hafızanın hangi kısmı denetlenir?** Kasadaki her dosya aynı standartta
değildir. **Canlı hafıza** — `AGENTS.md`/`CLAUDE.md` köprüleri, Konular
dosyası, Kurallar ve Çekirdek notları ve `Son-Oturum.md`'nin en yeni `## `
bloğu — bir sonraki oturumun üzerine kalkacağı talimattır; içindeki her yol
çalışmak zorundadır. **Tarihsel hafıza** — `Son-Oturum.md`'nin eski blokları,
Günlük notu, Oturumlar klasörü — kayıttır; artık var olmayan klasörleri
anmakta hakkı vardır ve yol denetimi ona hiç bakmaz. Yeni bir oturum bloğu
eklediğinizde eskisi kendiliğinden tarih olur.

Hafıza dosyalarının adları kasanın dilini izler (`Son-Oturum.md`/`Kurallar.md`/
`Çekirdek.md`/`Günlük.md`; İngilizce kasada `Last-Session.md`/`Rules.md`/
`Core.md`/`Journal.md`) ve öbür dildeki ad geri düşüş olarak kabul edilir.
Kasanız elle yazılmış bir hafıza dosyası taşıdığı anda bu küme **zorunlu**
olur: eksik bir dosya doctor'ın tek çıkış kodunu 1'e çeviren hafıza hatasıdır —
yarısı göçmüş bir hafıza katmanı, oturumların enjeksiyonlarını sessizce
kaybetmesidir.

Önemli satırlar nasıl okunur:

- **araçlar** bölümünde `hata` — `sh`, `sed`, `awk`, `grep`, `tr`, `git`
  bağımlılık listesinin tamamı. Eksik biri, Knotlog'u gerçekten durduran tek
  arıza türü.
- `uyarı index — index.tsv yok ya da bayat (knotlog index)` — yeni kasada, oturum
  dışında not düzenledikten sonra ve `remember`'ın hemen ardından beklenen bir
  uyarı; `remember` indeksin görmediği bir oturum notu yazar. `knotlog index`
  çalıştır.
- `uyarı threads — Konular.md henüz güncellenmemiş` — dosya yok ya da
  `Aktif/Kapanmış konular` bloğu hâlâ boş. İskeletin varlığı uyarıyı
  kaldırmaz, içine yazılan metin kaldırır. Yeni kasada normal, ilerleyen
  günlerde dürtme.
- `uyarı links — N wikilink hedefi vault'ta bulunamadı` — bir `[[bağlantı]]` hiçbir şeyi
  göstermiyor. Çözüm birebir eşleşmeyle olduğu için adı değişen bir not arkada
- `uyarı links — … birden çok nota karşılık geliyor` — iki not aynı adı taşıyor,
  Knotlog hangisi olduğunu tahmin etmeyi reddediyor.
- `hata hafıza — Son-Oturum.md | Last-Session.md kasada yok` — zorunlu hafıza
  dosyasından biri iki adıyla da bulunamıyor. Çıkış kodu 1 olur; diğer tüm
  hafıza bulguları uyarıdır.
- `uyarı yollar — N tırnak içi yol kasada bulunamadı` — canlı hafızadaki bir
  `` `tırnaklı/yol` `` kasada karşılıksız. Bulunamayan her yol sayının altında
  kendi satırında listelenir. `~/`, mutlak yollar, URL'ler, sürücü harfleri,
  jokerler ve kabuk parçaları hiç yargılanmaz; ardından argüman gelen bir kasa
  dosyası (`./knotlog doctor`) komut sayılır, yalın bir klasör adı (`lib/`) ise
  kasanın herhangi bir yerinde o adda bir klasör varsa bulunmuş sayılır.
- `uyarı yollar — … git'in yoksaydığı bir hedefe işaret ediyor` — yol var ama
  git onu izlemiyor: bu makinede çalışır, kasa klonlandığı ya da taşındığı gün
  kırılır.
- `uyarı hafıza — N hafıza dosyasında commit'lenmemiş değişiklik var` —
  hafızanın güvenlik ağı git'tir; commit edilmemiş hafızanın ağı yoktur.
  Commit atın.
- `uyarı son oturum — son oturum bloğu bugünün tarihini içermiyor` — bugünden
  commit var ama `Son-Oturum.md`'nin en yeni bloğu daha erken yazılmış.
  Bugünün tarihi bloğun tamamında aranır; gece yarısını geçen bir oturum
  yanlış alarm vermez.
- `ok claude hooks — kurulu (vault)` — adaptör `<kasa>/.claude/settings.json`
  içinde. Normal bir kurulum böyle görünür. Parantezsiz `kurulu`, adaptörün
  küresel `~/.claude/settings.json` içinde bulunduğu anlamına gelir. `kurulu
  değil` ise ikisi de yok demektir: 2. bölümdeki otomatik döngü çalışmıyor.
- `uyarı path — yol OneDrive içeriyor` / `locale UTF-8 değil` — emoji klasör
  adları ve katlama için ortam riskleri. İkisi de normal bir kasayı bozmaz.

`doctor` hiçbir şeyi değiştirmez. Bildirdiği her şey senin çalıştıracağın bir
komuttur.

## 8. Hook'suz kullanım

Hook yüzeyi olmayan ajanlar için — ya da döngüyü kendi elinde tutmak
istediğinde — otomatik kısmın yerini iki komut alır:

- `knotlog capture --git` çalışma ağacını son commit ile karşılaştırır ve değişen
  her Markdown dosyası için bir satır ekler. `remember`'dan önce çalıştır.
  Durumsuzdur: arada commit atmadan iki kez çalıştırırsan aynı dosyalar iki kez
  loglanır.
- `knotlog context --bridge` hook'ların enjekte edeceği bağlamı **hem**
  `AGENTS.md` **hem** `CLAUDE.md` içindeki `<!-- knotlog:context:start -->`
  bloğuna yazar. İki dosyadan hangisini okuyan ajan olursa olsun aynı hafızayı
  görür — bir ajanda yapılan işi diğerinin devralması böyle oluyor.

Elle bir oturum şöyle olur: `context --bridge` ile köprü dosyalarını tazele,
ajana birini okut, çalış, sonra
`knotlog capture --git && knotlog remember && knotlog index` çalıştır.

### Antigravity

Antigravity'nin hook yüzeyi var, bu yüzden otomatik döngüyü kullanır. Kasanın
içinden:

```
knotlog setup antigravity --dry-run   # önizleme, hiçbir şey yazmaz
knotlog setup antigravity             # .agents/hooks.json yazar
```

Oturum açılışında hook `remember` çalıştırır ve yakın bağlamı sistem mesajı
olarak enjekte eder. Ajan bir turu bitirirken ikinci bir hook oturum notunun
geride kalıp kalmadığına bakar (en fazla 30 dakikada bir) ve kaldıysa ajanı
tur kapanmadan notu yazmaya geri gönderir. Var olan ve farklı olan bir
`.agents/hooks.json` asla ezilmez; paketle gelen dosyayı
(`adapters/antigravity/hooks.json`) elle birleştir. Sonra Antigravity'yi
yeniden başlat. Ayrıntı: [REFERENCE.md](REFERENCE.md#antigravity).

### Devin Desktop (Windsurf) ve OpenCode

İkisi de küçük bir kayıt hook'u alır; bağlamları `AGENTS.md` köprüsünden gelir.
Kasanın içinden `knotlog setup windsurf` (ya da `devin`) ve
`knotlog setup opencode` çalıştır; `--dry-run` önizler. Sırasıyla
`.devin/hooks.json` ve `.opencode/plugins/knotlog.js` yazılır, farklı bir dosya
asla ezilmez. İstemci `knotlog`'u kendi ortamından çalıştırır (Devin Desktop
oturum açtığın kabuğu kullanır); bu yüzden `knotlog` o `PATH`'te olmalı, yoksa
hook sessizce hiçbir şey yapmaz. 25 Ekim 2026'da Linux'ta canlı doğrulandı
(Devin Desktop 3.11.216, OpenCode 1.19.4); Windows doğrulanmadı. Ayrıntı:
[REFERENCE.md](REFERENCE.md#windsurf--devin-desktop).

### MCP sunucusunu bağlamak

`knotlog mcp`, bir MCP istemcisinin hook olmadan kasada arama yapmasını ve
bağlamı okumasını sağlar. Üç araç sunar: `knotlog_search` (bir sorgu ve
isteğe bağlı sınır), `knotlog_context` ve `knotlog_note` (bugünkü oturum
notuna bir satır, `knotlog note` ile aynı). Kasayı başlatıldığı klasörden bulur;
bu yüzden kaydı kasanın içinden yap:

```
claude mcp add knotlog -- knotlog mcp
```

`knotlog` `PATH`'te değilse mutlak yolu ver. Başka bir istemci aynı komutu
`mcp` argümanıyla çalıştırabilir; kasanın dışında başlayan bir sunucu için
`KNOTLOG_VAULT`'u kasa klasörüne ayarla. Ayrıntı:
[REFERENCE.md](REFERENCE.md#mcp-server).

## 9. Ayar düğmeleri

Kasa ayarları `.knotlog/config` içinde düz `anahtar=değer` satırları hâlinde
durur: `layout`, `lang`, `fold`, `user`, `companion`, `purpose`, `tone`, `flair`,
`ctx_max`. `fold` değişince ardından `knotlog index --full` gerekir; diğerleri
bir sonraki komutta etkili olur. `ctx_max`'ı `init` kendiliğinden yazmaz —
zaten çalışan bir varsayılanı var (4096), satırı yalnız değiştirmek istersen
elle eklersin; `doctor` kullandığı değerin nereden geldiğini (ortam/config/
varsayılan) raporlar ve config'teki `ctx_max=` pozitif bir tamsayı değilse
uyarır (yok sayılır, hataya düşmez).

**Dil seçimi.** Knotlog English, Türkçe, Español, Português (Brasil), 日本語 ve
简体中文 konuşur. Dili kurulum sihirbazında, `--lang <kod>` ile (`en`, `tr`, `es`,
`pt-br`, `ja`, `zh-cn`) ya da `.knotlog/config` içindeki `lang=` ile seç; seçtiğin
dilde eksik olan şey İngilizceye düşer. İngilizce ve Türkçe dışındaki çeviriler
makine destekli, düzeltmelere açığız.

`tone`, dokuz hazır üslup setinden birini seçer (`knotlog tone --list` ad +
tarif gösterir, `knotlog tone <slug>` ayarlar) — kasanın dili için o preset
gerçekten varsa, `knotlog context`'e enjekte edilen üslup bloğunda
companion.md'nin kendi `## Üslup`/`## Tone` bölümünün önüne geçer. Boş
bırakırsan, ya da sunulmayan bir slug yazarsan, Knotlog companion.md'nin
Üslup bölümüne düşer — presetler var olmadan önceki davranışın aynısı.
`purpose` gibi, `init` sırasında `tone` için de soru sorulmaz; yalnız
`--tone <slug>` bayrağı vardır (`install` da kabul eder).

`flair` tonun üstüne bir yanıt süsü ekler: `none` (varsayılan), `kaomoji` ya da `emoji`. `knotlog flair` gösterir, `knotlog flair --list` listeler, `knotlog flair <değer>` ayarlar; `--flair` bayrağını `init` ve `install` de kabul eder. Metinler altı dilde de gelir. `none` dışındaki süs, `kaomoji` ton ön ayarının yerine geçer.

Varsayılanlar yetmezse ortam değişkenleri:

(Yeniden adlandırma öncesi `QUIPU_*` adları da çalışır; ikisi birden ayarlıysa `KNOTLOG_*` geçerlidir.)

- `KNOTLOG_CTX_MAX` (4096) — Knotlog'un enjekte ettiği bağlamın bayt bütçesi.
  `.knotlog/config`'teki `ctx_max=`'ın önüne geçer, o da 4096 varsayılanının
  önüne geçer — tek seferlik geçersiz kılma için ortam değişkenini, kasa
  başka makineye taşındığında da kalıcı bir ayar için config'teki `ctx_max=`
  satırını kullan.
- `KNOTLOG_NUDGE_AFTER` (50) — modele hafıza dürtmesi gitmeden önceki yeni log
  satırı sayısı.
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — oturum notu eskiyken ve kasada yeni iş varken
  ara kayıt uyarısı ya da engellemesi tetiklenmeden önceki saniye eşiği.
- `KNOTLOG_LOG_MAX` (262144) — `activity.log` bu boyutu aşınca `.log.1` olarak
  devreder.
- `KNOTLOG_HOOK=1` — adaptörler tarafından ayarlanır. Hataları 0 ile çıkmaya
  zorlar, böylece bozuk bir Knotlog oturumunu bloklamaz.

### Sır kapanı (pre-commit)

`install` kasayı varsayılan olarak Git deposu yapar (`--no-git` ile kapatılır),
bir açılış commit'i ve yeniden üretilen makine durumu için bir `.gitignore`
ekler; `init --git` aynısını istek üzerine yapar. Mevcut bir geçmişe asla yazılmaz,
git'siz tuttuğunuz mevcut bir kasa varsayılanla dönüştürülmez (dönüşmesini
istiyorsanız `--git` verin), git kimliği yoksa adım atlanır ve bildirilir,
kurulum çökmez. Kasa depo olduğu
sürece Knotlog `.githooks/pre-commit` kurar ve `core.hooksPath`'i ona çeker. Her
commit'te staged *eklenen* satırlar bilinen sır kalıplarına karşı taranır —
AWS `AKIA…`, OpenAI `sk-…`, GitHub `ghp_…`/`github_pat_…`, Slack `xox…`,
Google `AIza…`, `PRIVATE KEY` blokları ve jenerik `api_key=`/`secret=`/
`token=` atamaları — ve şüpheli dosyanın adı söylenerek commit reddedilir.
PATH'inizde harici bir `sir-tara` varsa taramanın tamamı ona devredilir.
Elle düzenlenmiş bir hook (knotlog imzası taşımayan) asla ezilmez. Yine de
commit etmek için: `git commit --no-verify` bütün hook'ları atlar;
`KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` yalnız bu kapanı, yalnız o commit
için atlar.

`knotlog help` bütün komutları listeler; `knotlog help --tr` aynı listeyi Türkçe
basar (gönderilen diğer diller de aynı şekilde: `--es`, `--pt-br`, `--ja`, `--zh-cn`).

## 10. Amnezi testi

Knotlog'un ne işe yaradığının en kısa kanıtı. Kendin uygula:

1. Ajanla gerçek bir iş yap — kararlar ver, not yaz, bir konuyu kapat.
2. Oturumu kapat. Bilgisayarı yeniden başlat.
3. Yeni bir oturum aç ve tek soru sor: *"Dün ne yapmıştık?"*

Kurulumdan önce cevap: "Önceki konuşmalara erişimim yok."
Kurulumdan sonra cevap: dünün kendisi — kararlar, gerekçeleri ve kaldığın
yer; modelin hafızasından değil, kasadan okunarak.

## 11. Ayrılmak

Knotlog sana uymadıysa, makineni geri almak tahmin işi olmamalı. Kaldırma komutu
yalnızca kurulumun kasanın **dışına** koyduğu şeyi siler:

```bash
knotlog uninstall --dry-run   # ne gideceğini göster
knotlog uninstall             # komutu PATH'ten kaldır
```

Windows'ta bunun yerine PowerShell'den `.\uninstall.ps1` çalıştır (iki şekilde de
kurduysan ikisini de) — `%LOCALAPPDATA%\Knotlog\bin` altındaki shim'leri ve
kullanıcı `PATH`'ine eklediği girdiyi kaldırır.

**Notların asla silinmez.** Kasa tam olarak durduğu yerde kalır; komut çıkışta
kasanın yolunu ve içinde kalan Knotlog dosyalarını yazar. O dosyalar komut olmadan
işlevsiz — kasa o noktada sadece klasörlerdeki Markdown'dır; saklayabilir,
taşıyabilir ya da kendin silebilirsin. Silmek istersen komut sana tam olarak
hangi satırı yazacağını gösterir.

Makinende başka hiçbir şey değişmedi: Knotlog kabuk açılış dosyalarını hiç
düzenlemez, kasa ve kendi komut shim'i dışına hiçbir şey yazmaz, ve dışarıya
hiçbir veri göndermez.
