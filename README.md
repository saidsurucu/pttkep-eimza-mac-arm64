# PTT KEP E-İmza — Native Apple Silicon (arm64) .app

[PTT KEP](https://pttkep.gov.tr) Webmail E-İmza Uygulaması, bir Java Web
Start (JNLP) uygulamasıdır. Java Web Start, Java 11+ ile kaldırıldığından
uygulama modern Mac'lerde kolayca açılamıyor. Bu depo, uygulamayı **gömülü
arm64 Java 11 runtime'ı** ile **çift tıklayıp açabileceğiniz native bir
`.app`'e** paketler — Rosetta gerektirmez, ayrıca Java kurmanıza gerek kalmaz.

> ⚠️ **Bu depo PTT KEP E-İmza uygulamasının kaynak kodunu içermez.** Tamamen
> bağımsız, **gayriresmî** bir Mac **paketleyicisidir**: hiçbir kamu kurumu
> tarafından geliştirilmemiş/onaylanmamıştır. Burada bulunan yalnızca paketleme
> ve build betikleridir; resmî `elektronik-imza.jar`'ı build sırasında
> ptt.hs01.kep.tr'den **siz** indirir ve native `.app`'i **siz** üretirsiniz.
> "Olduğu gibi" sunulur.

> ✅ Apple Silicon'da **gerçek kartla tam imzalama** (sertifika → PIN → imza)
> doğrulandı. (Tek bir kurulumda test edildi; yine de farklı kart/sürücü
> sürümlerinde değişiklik olabilir.)

---

# 👩‍💼 Kolay kurulum — tek satır

Programcı olmanıza gerek yok. **Terminal** uygulamasını açın (klavyede
`Command (⌘) + Boşluk`'a basıp açılan kutuya **Terminal** yazın ve **Enter**'a
basın), ardından aşağıdaki **tek satırı** kopyalayıp yapıştırın ve **Enter**'a
basın:

```bash
curl -fsSL https://raw.githubusercontent.com/saidsurucu/pttkep-eimza-mac-arm64/main/kur.sh | bash
```

Hepsi bu kadar. Manuel indirme, klasöre girme, Java kurma gibi adımlar **yok**. Bu
komut gerisini sizin için yapar:

- Gerekiyorsa **geliştirici araçlarını** (Xcode komut satırı araçları) kurar — bir
  pencere açılırsa yalnızca **"Yükle"**ye basıp bitmesini bekleyin, betik
  kendiliğinden devam eder.
- **Kaynak kodu** `~/pttkep-eimza-mac-arm64` klasörüne indirir (zaten varsa en
  güncel sürüme günceller).
- Gereken **Java** sürümlerini otomatik indirir.
- Resmî `elektronik-imza.jar`'ı ptt.hs01.kep.tr'den indirir, uygulamayı **derler +
  imzalar** ve doğrudan **/Applications** klasörüne kurar.

İlk derleme internet hızınıza göre birkaç dakika sürebilir.

Bittiğinde uygulama **Launchpad** ve **Applications** klasöründe hazırdır; çift
tıklayarak açabilirsiniz. (Kendiniz derleyip imzaladığınız için macOS "geliştirici
doğrulanamadı" uyarısı **çıkmaz**; `xattr` ile uğraşmanıza gerek yoktur.)

**Yeni sürüm çıktığında yukarıdaki tek satırı yeniden çalıştırmanız yeterli. En
güncel sürüm otomatik inecek ve paketlenecek.**

> İsterseniz sürükle-bırak yerleşimli bir `.dmg` de üretebilirsiniz:
> `brew install create-dmg` sonrası `make dmg`.

> ⚠️ **E-imza için arm64 AKİS sürücüsü ŞART** (aşağıdaki bölüm). Uygulama native
> arm64'tür; kart sürücünüz de arm64 olmalıdır.

---

## ⚠️ Apple Silicon (arm64) AKİS sürücüsü kurulumu (zorunlu)

Bu uygulama native arm64 çalışır. **Bir arm64 uygulama, yalnızca Intel (x86_64)
derlenmiş bir sürücüyü yükleyemez** (mimari uyuşmazlığı). TÜBİTAK AKİS'in macOS
için **ayrı Intel ve Apple Silicon paketleri** vardır; çoğu kullanıcıda
eski/Intel sürüm kuruludur.

**Çözüm:** Apple Silicon AKİS paketini kurun:

1. [TÜBİTAK BİLGEM AKİS — Destek/İndirme](https://akiskart.bilgem.tubitak.gov.tr/tr/destek/)
   sayfasından **"Mac OS Arm (Apple Silicon)"** başlığı altındaki güncel paketi indirin
   (ör. `Akia_macos_arm_6_8_9.pkg`). **"Mac OS Intel" paketini değil**, Arm paketini seçin.
2. İndirilen `.pkg`'a çift tıklayıp kurulumu tamamlayın (yönetici şifresi ister).
3. **PTT KEP E-İmza** uygulamasını kapatıp yeniden açın; kartı takıp deneyin.

**Doğru sürümü kurduğunuzu teyit:** Terminal'de şu komut **`x86_64 arm64`** (veya
en azından `arm64`) yazmalı — sadece `x86_64` yazıyorsa hâlâ Intel sürüm kuruludur:

```
lipo -archs /usr/local/lib/libakisp11.dylib
```

---

# 🛠️ Mühendisler için — Teknik ayrıntı

Yukarıdaki adımlar derlemek için yeterlidir. Bu bölüm, tek tek build hedeflerini
ve dönüşümün **neyi nasıl** çözdüğünü açıklar. Gereksinimler kendiliğinden kurulur
(Azul Zulu 11 + 21). Apple Silicon Mac'te:

```bash
make all          # download → icns → package → sign
make run          # üretilen .app'i aç
make dmg          # sürükle-bırak yerleşimli .dmg üret (brew install create-dmg gerekir)
```

DMG arka planı `assets/dmg-background.svg`'den üretilir; düzenleyip `make assets`
ile yeniden render edebilirsiniz (`brew install librsvg`). Tek tek hedefler için `make help`.

### Nasıl çalışır

- `jpackage --type app-image` + `--runtime-image <tam arm64 Zulu 11>` ile
  uygulama ve **gömülü Java 11 runtime** tek bir native `.app`'e paketlenir.
  Tam JRE şarttır (jlink-strip değil): smartcardio/crypto provider'ları gerekir.
- **Neden Java 11:** otomatik HiDPI (JEP 263) → Retina'da keskin metin
  (arm64 Java 8 Swing bulanık render ediyor). `elektronik-imza.jar` Java 7
  bytecode'dur (major 51) ve Java 11'de sorunsuz çalışır.
- **`-Djnlp.config` (kritik):** JNLP, uygulamaya
  `jnlp.config=https://ptt.hs01.kep.tr/download/config.properties` property'sini
  geçirir; sunucu adresleri (getVersion/eSign) bu dosyadan okunur. jpackage
  `--java-options` ile bu property `.app`'e gömülür — yoksa uygulama sunucuyu
  bulamaz.
- **Kart erişimi (e-Devlet'ten fark):** PTT KEP jar'ı IAIK PKCS#11 wrapper
  DEĞİL, TÜBİTAK ESYA API (`APDUSmartCard`) + `javax.smartcardio` kullanır;
  jar'da kart erişimi için native kütüphane taşınmaz. Bu yüzden e-Devlet
  paketleyicisindeki Javassist connect-fix patch'i burada gerekmez. AKİS
  middleware'inin arm64 sürümü sistemde kurulu olmalıdır.
- **İkon:** codebase'deki `logo.png` 404 verdiğinden ikon jar içindeki
  `images/logo.png`'den (200×200) çıkarılıp `.icns`'e dönüştürülür.
- **codesign + Türkçe karakter:** `.app` adındaki `İ` gibi karakterler imzayı
  bozuyor; bu yüzden executable ASCII tutulur (`PTTKEPEImza`), görünen ad
  sonradan `CFBundleName`/`CFBundleDisplayName` ile Türkçe yapılır. Ad-hoc imza
  (`codesign -s -`) uygulanır.

### JNLP gerçekleri (kaynak)

| Alan | Değer |
|------|-------|
| codebase | `https://ptt.hs01.kep.tr/download` |
| ana jar | `elektronik-imza.jar` (~26 MB, self-contained) |
| main-class | `tr.gov.ptt.kep.digitalsignature.swing.FrmApplet` |
| j2se | 1.7+ · all-permissions |
| jnlp.config | `https://ptt.hs01.kep.tr/download/config.properties` (sunucu adresleri) |
| sürüm | `1.2.5` (pencere başlığı; config'teki `applet.version=10.0.1` applet protokol sürümüdür) |
| ikon | jar içi `images/logo.png` → `.icns` |

---

## CI build (isteğe bağlı)

`.github/workflows/release.yml` elle tetiklenir (`workflow_dispatch`):
macos-14 (arm64) runner'da `.app` üretir, mimariyi+imzayı doğrular ve
`<APP_VERSION>_<N>` etiketli bir yayın oluşturur.
