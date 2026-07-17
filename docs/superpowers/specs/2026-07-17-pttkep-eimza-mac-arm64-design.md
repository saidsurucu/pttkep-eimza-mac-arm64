# PTT KEP E-İmza — Native Apple Silicon (arm64) .app Paketleyici — Tasarım

Tarih: 2026-07-17
Durum: Onaylandı (kullanıcı, sohbet içinde)

## Amaç

PTT KEP Webmail E-İmza Uygulaması (`pttkep-eimza.jnlp`, Java Web Start) modern
Mac'lerde açılamıyor (JWS Java 11+ ile kaldırıldı). Bu repo, resmî
`elektronik-imza.jar`'ı kullanıcının kendisinin indirip **gömülü arm64 Java 11
runtime'lı native bir `.app`'e** paketlemesini sağlar —
[edevlet-eimza-mac-arm64](https://github.com/saidsurucu/edevlet-eimza-mac-arm64)
reposuyla **birebir aynı mantıkta**: kur.sh tek satır kurulum, Makefile,
scripts/build.sh, README, CI doğrulama build'i, DMG üretimi. Hazır paket
dağıtılmaz; kullanıcı kendisi derler.

## Kaynak gerçekleri (keşifle doğrulandı)

| Alan | Değer |
|------|-------|
| codebase | `https://ptt.hs01.kep.tr/download` |
| ana jar | `elektronik-imza.jar` (~26 MB, self-contained fat jar) |
| main-class | `tr.gov.ptt.kep.digitalsignature.swing.FrmApplet` |
| bytecode | Java 7 (major 51) → Java 11'de çalışır |
| JNLP property | `jnlp.config=https://ptt.hs01.kep.tr/download/config.properties` (**kritik**: uygulama sunucu URL'lerini buradan okur) |
| uygulama sürümü | `10.0.1` (config.properties `applet.version`) |
| ikon | codebase'deki `logo.png` **404** → jar içindeki `images/logo.png` (200×200) kullanılacak |
| kart erişimi | TÜBİTAK ESYA API (`APDUSmartCard`) + `javax.smartcardio`; jnasmartcardio sınıfları gömülü ama JNA yok → JVM'in yerleşik smartcardio'su kullanılıyor. **IAIK PKCS#11 wrapper YOK** → edevlet'teki Javassist connect-fix patch'i gerekmez. |
| sqlite | 2010 tarihli xerial sqlite-jdbc; Mac native'leri sadece i386/x86_64 (arm64 yok); eski sürümün pure-Java fallback'i beklenir |

## Repo yapısı

```
pttkep-eimza-mac-arm64/
├── kur.sh                          # tek satır kurulum (edevlet kur.sh uyarlaması)
├── Makefile                        # make all/run/dmg/help → scripts/build.sh'a delege
├── README.md                       # edevlet README yapısı birebir, PTT KEP içeriği
├── .gitignore                      # build/, downloads/ hariç
├── .github/workflows/release.yml   # macos-14 arm64 doğrulama build'i (workflow_dispatch)
├── assets/dmg-background.svg       # PTT KEP için uyarlanmış DMG arka planı (+ üretilen png/tiff)
├── scripts/build.sh                # ana build hattı
├── docs/superpowers/specs|plans/   # tasarım + plan belgeleri
└── pttkep-eimza.jnlp               # kaynak JNLP (referans)
```

`scripts/PreallocPatch.java` **yok** (IAIK patch'i bu jar'da gereksiz).

## build.sh tasarımı

Edevlet `scripts/build.sh`'ının uyarlaması. Hedefler aynı: `all`,
`check-deps`, `jdk`, `jpackage-jdk`, `download`, `icns`, `package`, `sign`,
`run`, `assets`, `dmg`, `clean`, `distclean`, `help`.

Sabitler:

| Değişken | Değer |
|----------|-------|
| `APP_NAME` | `PTT KEP E-İmza` (görünen ad, Türkçe) |
| `ASCII_NAME` | `PTTKEPEImza` (executable; codesign Türkçe karakterle bozuluyor) |
| `BUNDLE_ID` | `tr.gov.ptt.kep.digitalsignature` |
| `MAIN_CLASS` | `tr.gov.ptt.kep.digitalsignature.swing.FrmApplet` |
| `MAIN_JAR` | `elektronik-imza.jar` |
| `APP_VERSION` | `10.0.1` (env ile geçilebilir) |
| `CODEBASE` | `https://ptt.hs01.kep.tr/download` |
| `CONFIG_URL` | `$CODEBASE/config.properties` |

Edevlet'e göre farklar:

1. **`--java-options '-Djnlp.config=<CONFIG_URL>'`** eklenir (JNLP'deki
   property; olmadan uygulama sunucu adreslerini bulamaz).
   `-Djava.net.preferIPv4Stack` PTT JNLP'sinde yok → eklenmez.
2. **İkon**: `download` adımında `unzip -p elektronik-imza.jar images/logo.png`
   ile jar'dan çıkarılır; `icns` adımı 200×200 kaynaktan iconset üretir
   (16–256 küçültme, 512 upscale — edevlet'teki mantığın 200 tabanlı hâli).
3. **Jar doğrulama**: manifest `Main-Class` kontrolü kalır; IAIK arm64 native
   lib kontrolü **kaldırılır**.
4. **Patch adımı yok**: Javassist/PreallocPatch tamamen çıkar. Kart testinde
   sorun çıkarsa patch adımı o zaman eklenir (aşağıdaki riskler).

Aynı kalanlar: gömülü tam arm64 Zulu 11 runtime (`--runtime-image`, HiDPI/JEP
263 için Java 11), jpackage için Zulu 21, Azul API'den otomatik JDK indirme,
`--type app-image`, `CFBundleName`/`CFBundleDisplayName` ile Türkçe görünen ad,
`NSHighResolutionCapable`, ad-hoc `codesign -s -` + strict doğrulama,
create-dmg ile sürükle-bırak DMG, `rsvg-convert`+`tiffutil` ile HiDPI arka plan.

## kur.sh

Edevlet `kur.sh` birebir; değişenler: repo URL'si
(`saidsurucu/pttkep-eimza-mac-arm64`), hedef klasör
(`~/pttkep-eimza-mac-arm64`), uygulama/ürün adları. Akış: Xcode CLT kontrolü →
git clone/pull → `make all` → `/Applications`'a kopyalama.

## README

Edevlet README bölüm yapısı birebir: başlık + ne yaptığı, resmî-değil ve
kaynak-kod-içermez uyarısı, hazır paket dağıtılmaz notu, tek satır kurulum,
arm64 AKİS sürücüsü bölümü (zorunlu; belirti + çözüm + `lipo -archs` teyidi),
mühendisler için teknik ayrıntı (make hedefleri, nasıl çalışır, JNLP gerçekleri
tablosu), CI notu. Kartla doğrulama durumu test sonucuna göre yazılır
(doğrulandı / test edilmedi).

## CI (release.yml)

Edevlet workflow'unun birebir uyarlaması: `workflow_dispatch` (yalnız elle
tetik), macos-14 (arm64) runner, `make all`, mimari + `codesign --verify`
doğrulaması, `<APP_VERSION>_<N>` etiketiyle DMG'li GitHub Release üretimi.
Release üretip üretmemek tetikleme anında kullanıcının kararıdır; otomatik
tetikleyici yoktur.

## Test planı (build sonrası, kullanıcı gerçek kartla)

Akış: `.app` açılış → kart algılama → sertifika listesi → PIN → imza → PTT KEP
webmail'de doğrulama.

Bilinen riskler ve hazır çözümler (ancak test kanıtlarsa uygulanır):

1. **CryptoTokenKit `beginExclusive` çakışması** (adalet-eimza-mac-arm64
   reposunda teşhisli: `ctkpcscd` kartı tutunca `SCARD_E_READER_UNAVAILABLE`)
   → çözüm şablonu: `-javaagent` ile `beginExclusive` no-op.
2. **sqlite arm64 native yok** → pure-Java fallback beklenir; çalışmazsa
   ude-mac-arm'daki native-swap yaklaşımı uyarlanır.
3. **TLS** (`ssl_check=false` config'te mevcut) → sorun çıkarsa
   `--java-options`'a ilgili bayraklar eklenir.

## Kapsam dışı

- Uygulamanın kaynak koduna müdahale / yeniden yazım.
- Hazır paket (release binary) dağıtımı.
- Intel (x86_64) Mac desteği.
