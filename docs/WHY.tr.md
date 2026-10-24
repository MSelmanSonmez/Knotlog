# Neden Knotlog

## Sorun

Bugün bir terminal ajanı açtığında, dünden hiçbir şey bilmiyor.

Dün gece onunla üç saat çalıştın. Projeyi anlattın. İki yaklaşımı gerekçesiyle
birlikte eledin. Üçüncüsünde karar kıldın. Bu sabah aynı klasörde aynı ajanı
açıyorsun ve bunların hiçbiri orada değil. Sen de baştan anlatıyorsun. Bu sefer
daha kısa, çünkü anlatmaktan bıktın — yani daha kötü versiyonunu anlatıyorsun.

Bütün mesele bu. Model zayıf olduğu için değil; model gayet iyi. Sadece her
oturuma sıfırdan başlıyor ve o boşluğu her seferinde sen sırtlıyorsun.

Birkaç hafta sonra ne yapmaya başladığını fark ediyorsun. Oturum başında
yapıştırmak için bir kenarda not tutuyorsun. Uzun oturumlara giriyorsun çünkü
yeniden başlamak pahalı. "Bunu neden böyle yapmıştık" diye sormayı bırakıyorsun,
çünkü kimse hatırlamıyor — sen dahil.

## Knotlog ne yapıyor

Knotlog olan biteni Markdown olarak tek bir klasöre yazıyor.

Ajan çalışırken okuduğu ya da yazdığı her dosya bir log dosyasına tek satır
olarak ekleniyor. Oturum kapanınca o satırlar tarihli bir nota dönüşüyor. Bir
sonraki oturum açıldığında, sen daha hiçbir şey yazmadan, son etkinlik ve açık
konular modelin bağlamına geri basılıyor.

Yani yarın sabah ajanı açtığında dün gece neyi neden yaptığını biliyor.
Hatırladığı için değil — okuduğu için.

Fikrin tamamı bu. Sayfanın geri kalanı, neden böyle kurulduğunu anlatıyor.

## Neden hiçbir şeye mal olmuyor

İlk sorulan soru genelde bu oluyor, çünkü kodlama ajanları için yazılmış hafıza
araçlarının çoğu altyapı parası istiyor.

Ve haklı bir sebeple istiyor. claude-mem gibi bir araç, bir oturumun ne anlama
geldiğine karar vermek için ayrı bir işlem çalıştırıyor. O işlemin içinde model
yok, dolayısıyla modeli dışarıdan bulması gerekiyor: geri getirme için bir vektör
veritabanı, onu doldurmak için gömmeler, gömmeleri üretmek için bir API anahtarı.
Gerçek altyapı, gerçek maliyet — ve fatura sana geliyor.

Knotlog'da bu sorun yok, çünkü ikinci bir beyne hiç ihtiyaç duymadı. Ajan zaten
çalışıyor. Parasını zaten ödüyorsun. Yani anlamı çıkaran katman, döngüde zaten
duran modelin kendisi — Knotlog ona sadece yazacak bir yer veriyor ve doğru anda
geri okuyor.

Veritabanı yok. Gömme yok. API anahtarı yok. Faturalanacak bir şey de yok,
çünkü para harcayabilecek hiçbir şey çalışmıyor.

## Dosyalar senin

Hafızan, senin seçtiğin bir klasörde duran Markdown dosyaları.

İstediğin editörde aç. Hiçbir araç kullanmadan oku. Git'e koy ve aylar içinde
kendi düşüncenin nasıl değiştiğini izle. Obsidian'a taşı, başka bir hafıza
aracına geç, ya da beş yıl sonra düz bir metin editöründe aç.

Dışa aktaracak bir şey yok, çünkü hiçbir şey tek bir programın okuyabildiği bir
biçime sokulmadı. Knotlog bu dosyalara ekleme yapar; senin yazdığını asla yeniden
yazmaz. Yarın Knotlog'u silsen, kaydettiği her şey yerinde ve okunabilir kalır.

## Çevrimdışı ve yerel

Knotlog hiçbir ağ isteği yapmıyor. İçinde `curl` yok, yükleme yok, telemetri yok,
hesap yok.

Notların senin diskinde. Ajanın gece ikide neye dokunduğu senin diskinde. Müşteri
koduyla çalışıyorsan, gizlilik sözleşmesi altındaki bir şeye bakıyorsan ya da
uçaktaysan bu fark eder. Ayrıca şu anlama gelir: bir servis çöktü, fiyatını
değiştirdi ya da ücretsiz katmanını kapattı diye Knotlog bozulamaz.

## Sıfır bağımlılık

Knotlog tek bir POSIX kabuk betiği. Kullandıkları: `sed`, `awk`, `grep`, `tr`, ve
`git` — makinende zaten duran araçlar.

Python yok. Node yok. `jq` yok. `npm install` edilecek bir şey yok, bir çalışma
zamanı sürümüyle senkron tutulacak bir şey yok, altı ay sonra alakasız bir şeyi
güncellediğinde bozulacak bir şey yok.

Bu bir sadelik övünmesi değil. Kurulumun neden çalıştığının sebebi. Çözülecek bir
bağımlılık ağacı yok, dolayısıyla kurulumun takılabileceği bir yer de yok. Test
paketi her commit'te Linux, macOS ve Windows üzerinde koşuyor — çünkü üçünde de
aynı betik çalışıyor.

## Türkçe ve İngilizce, ikisi de gerçekten

Çoğu araç İngilizce dışını en sona eklenen bir çeviri katmanı gibi görüyor.
Burada iş arayüz metinlerinden daha derine iniyor.

Arama, hem indekslerken hem sorgularken metni katlıyor. Türkçe bir kasada
`İ ı ğ ş ç ö ü` iki tarafta da ASCII karşılıklarına iniyor, böylece `acik kaynak`
ile `açık kaynak` aynı notu buluyor. O katlama gerçek bir karakter haritası,
kural kural yazılmış — noktalı İ'yi öğüten ve işi bitmiş sayan iyimser bir
`lowercase()` çağrısı değil.

Arayüz, klasör yerleşimi, yardım metni, hazır şablonlar ve asistan personası
iki dilde de var. Kurulumda birini seçiyorsun, kasa o dilde kuruluyor.

## Ne değil

Knotlog, yazdıklarını anlayan bir arama motoru değil. Araması sözcük temelli ve
BM25 ile sıralanıyor — yarım hatırladığın bir notu bulmakta iyi, o notla ilgili
bir soruyu cevaplamakta değil. Anlama işi olması gereken yerde oluyor: sonuçları
okuyan modelde.

Knotlog yansımalarını da senin yerine yazmıyor. Olanı mekanik olarak kaydediyor —
dosyalar, saatler, araçlar — ve her oturum notunda yalnızca senin ya da modelin
doldurabileceği kısım için bir iskelet bırakıyor: ne değişti, neden. Kimse
doldurmazsa doldurulmaz. Knotlog biçimi zorunlu tutar, anlamı değil.

Yapıyla ilgili aklından geçeni de okumuyor. Yazdığın notları indeksler.
Senin yerine not uydurmaz.

## Kısa özet

Bir kodlama ajanını her gün kullanıyorsan, hafıza sorunun zaten var. Ve zaten
elle çözüyorsun — kötü bir şekilde, yapıştırılan bağlamla ve bir kenardaki not
dosyasıyla.

Knotlog, o işi senin yerine yapan küçük bir betik. Senin sahip olduğun dosyalara,
senin kalmaya devam eden makinende, bedavaya.

Buradan başla: kurulum için [README](../README.md), günlük döngü için
[kullanım kılavuzu](GUIDE.tr.md).
