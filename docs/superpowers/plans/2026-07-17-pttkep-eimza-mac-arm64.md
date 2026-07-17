# PTT KEP E-İmza arm64 Paketleyici — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PTT KEP Webmail E-İmza JNLP uygulamasını, edevlet-eimza-mac-arm64 reposuyla birebir aynı mantıkta, gömülü arm64 Java 11 runtime'lı native `.app`'e paketleyen repo.

**Architecture:** Tek bash build hattı (`scripts/build.sh`) + ince Makefile sarmalayıcı + tek satır kurulum betiği (`kur.sh`) + elle tetiklenen CI. Resmî 26 MB `elektronik-imza.jar` build sırasında `ptt.hs01.kep.tr`'den indirilir, jpackage `--type app-image` + `--runtime-image` (tam arm64 Zulu 11) ile paketlenir, ad-hoc imzalanır. Edevlet'teki IAIK/Javassist patch'i YOK (bu jar ESYA API + javax.smartcardio kullanıyor); kritik ek: `-Djnlp.config=<config.properties URL>` java option'ı.

**Tech Stack:** bash, make, jpackage (Zulu 21), Azul Zulu 11 arm64 runtime, sips/iconutil, codesign, create-dmg, rsvg-convert+tiffutil, GitHub Actions (macos-14).

## Global Constraints

- Tüm kullanıcı-yüzü metinler ve yorumlar **Türkçe** (edevlet üslubu).
- Görünen ad `PTT KEP E-İmza`; executable/`CFBundleExecutable` **ASCII**: `PTTKEPEImza` (codesign Türkçe karakterle bozuluyor).
- `BUNDLE_ID=tr.gov.ptt.kep.digitalsignature`, `MAIN_CLASS=tr.gov.ptt.kep.digitalsignature.swing.FrmApplet`, `MAIN_JAR=elektronik-imza.jar`, `APP_VERSION=10.0.1`.
- Codebase: `https://ptt.hs01.kep.tr/download`; jpackage'a `--java-options '-Djnlp.config=https://ptt.hs01.kep.tr/download/config.properties'` **şart**.
- İkon: jar içindeki `images/logo.png` (200×200) — codebase'deki `logo.png` 404 verir, **curl ile ikon indirilmez**.
- `build/` ve `downloads/` git'e girmez; jar repoya konmaz.
- Sadece Apple Silicon (arm64) hedeflenir; commit mesajları Türkçe + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Şablon repo: `/Users/saidsurucu/Documents/GitHub/edevlet-eimza-mac-arm64` (yerel, referans için okunabilir).
- Çalışma dizini: `/Users/saidsurucu/Documents/GitHub/pttkep-eimza-mac-arm64` (git init edilmiş, spec commit'li).

---

### Task 1: Repo iskeleti — .gitignore + Makefile

**Files:**
- Create: `.gitignore`
- Create: `Makefile`

**Interfaces:**
- Produces: `make <hedef>` → `bash scripts/build.sh <hedef>` delegasyonu. Hedef adları: `all check-deps jdk jpackage-jdk download icns package sign run assets dmg clean distclean help` (Task 2'deki build.sh case'iyle birebir eşleşmeli).

- [ ] **Step 1: .gitignore yaz**

```gitignore
# Build çıktıları
/build/

# İndirilen kaynaklar (jar, ikon, Zulu arşivleri) — yeniden indirilebilir
/downloads/

# macOS
.DS_Store
._*
```

- [ ] **Step 2: Makefile yaz**

```makefile
# PTT KEP E-İmza — native Apple Silicon (arm64) build
# Asıl mantık scripts/build.sh içinde. Bu Makefile ince bir sarmalayıcıdır.

SH := bash scripts/build.sh

.PHONY: all check-deps jdk jpackage-jdk download icns package sign run assets dmg clean distclean help

all: ## ARM64 .app'i üret (varsayılan)
	@$(SH) all

check-deps: ## Araçları, arm64 Java 11 ve jpackage'ı denetle
	@$(SH) check-deps

jdk: ## Gömülecek arm64 Java 11 yoksa Azul Zulu 11 kur
	@$(SH) jdk

jpackage-jdk: ## jpackage'lı 17+ JDK yoksa Azul Zulu 21 kur
	@$(SH) jpackage-jdk

download: ## elektronik-imza.jar indir + doğrula + ikonu jar'dan çıkar
	@$(SH) download

icns: ## .icns ikon üret
	@$(SH) icns

package: ## jpackage ile .app üret (Java 11 gömülü)
	@$(SH) package

sign: ## ad-hoc codesign
	@$(SH) sign

run: ## üretilen .app'i aç
	@$(SH) run

assets: ## DMG arka planını assets/dmg-background.svg'den üret
	@$(SH) assets

dmg: ## sürükle-bırak yerleşimli .dmg üret (create-dmg gerekir)
	@$(SH) dmg

clean: ## build/ sil (indirilenleri korur)
	@$(SH) clean

distclean: ## build/ + indirilenler sil
	@$(SH) distclean

help: ## Bu yardım
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```

(Makefile girintileri TAB olmalı — boşluk değil.)

- [ ] **Step 3: Doğrula**

Run: `cd /Users/saidsurucu/Documents/GitHub/pttkep-eimza-mac-arm64 && make help`
Expected: hedef listesi (all, check-deps, …) alfabetik sıralı yazdırılır, hata yok.

- [ ] **Step 4: Commit**

```bash
git add .gitignore Makefile
git commit -m "Repo iskeleti: .gitignore + Makefile sarmalayıcı

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: scripts/build.sh — ana build hattı

**Files:**
- Create: `scripts/build.sh`

**Interfaces:**
- Consumes: Task 1'in Makefile hedef adları.
- Produces: `build/PTT KEP E-İmza.app` (package+sign sonrası), `build/PTTKEPEImza.icns`, `downloads/elektronik-imza.jar`, `downloads/logo.png`. `DMG_OUT` env ile DMG çıkış yolu (CI kullanır). `APP_VERSION` ve `JAR_URL` env ile ezilebilir.

Edevlet `scripts/build.sh`'ından farklar (uygularken bilinçli yapılacaklar):
1. IAIK/Javassist patch altyapısı TAMAMEN YOK (`fetch_javassist`, `patch_jar`, `jpackage_home`, `PATCHER_SRC`, `JAVASSIST_*`, `PATCH_*` yok).
2. `download`: ikon curl ile İNMEZ; jar'dan `unzip -p … images/logo.png` ile çıkarılır.
3. Jar doğrulama: manifest `Main-Class` + `images/logo.png` varlığı (IAIK arm64 native lib kontrolü yok — bu jar'da IAIK yok).
4. `--java-options '-Djnlp.config=…'` (edevlet'teki `preferIPv4Stack` PTT JNLP'sinde yok → konmaz).
5. `icns`: kaynak 200×200 → 16/32/128 gerçek küçültme, 256/512 upscale.

- [ ] **Step 1: scripts/build.sh yaz**

```bash
#!/bin/bash
#
# build.sh — PTT KEP Webmail E-İmza için native Apple Silicon (arm64) .app üretir.
#
# Kaynak: https://ptt.hs01.kep.tr/download/pttkep-eimza.jnlp
#   Java Web Start uygulaması; JWS Java 11+'da kaldırıldığı için Mac'te açılamıyor.
#   Çözüm: ana jar + main-class'ı jpackage ile arm64 **Java 11** runtime'ı GÖMÜLEREK
#   çift-tıkla açılan native .app'e paketle.
#
# Neden Java 11 (Java 8 değil):
#   - Java 11 = otomatik HiDPI (JEP 263) → Retina'da KESKİN metin (Java 8 arm64 Swing bulanık).
#   - elektronik-imza.jar = Java 7 bytecode (major 51) → Java 11'de sorunsuz çalışır.
#
# Kart erişimi (KRİTİK FARK — e-Devlet'ten):
#   - PTT KEP, IAIK PKCS#11 wrapper DEĞİL, TÜBİTAK ESYA API (APDUSmartCard) +
#     javax.smartcardio kullanır (jnasmartcardio sınıfları gömülü ama JNA yok →
#     JVM'in yerleşik smartcardio'su devrede). Jar'da IAIK native'i yok.
#   - Bu yüzden e-Devlet'teki Javassist connect-fix patch'i GEREKMEZ.
#   - AKİS için kullanıcıda arm64 AKİS middleware kurulu olmalı.
#
# Kritik ek (e-Devlet'te yoktu):
#   - JNLP, uygulamaya jnlp.config property'si geçirir; sunucu adresleri
#     (getvers/getdata/setdata) bu config.properties'ten okunur. .app'e
#     -Djnlp.config=<URL> gömülmezse uygulama sunucuyu bulamaz.
#
# Tam JRE şart (jlink-strip DEĞİL): smartcardio/crypto provider'ları için
#   --runtime-image <tam arm64 Zulu 11>.
#
# + ASCII executable adı (codesign Türkçe karakterle bozuluyor) + ad-hoc imza
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$ROOT/build"
DOWNLOADS="$ROOT/downloads"

APP_NAME="PTT KEP E-İmza"           # görünen ad (Türkçe)
APP="$BUILD/$APP_NAME.app"
ASCII_NAME="PTTKEPEImza"            # executable/CFBundleExecutable (ASCII şart, codesign)
BUNDLE_ID="tr.gov.ptt.kep.digitalsignature"
MAIN_CLASS="tr.gov.ptt.kep.digitalsignature.swing.FrmApplet"
MAIN_JAR="elektronik-imza.jar"
# Görünen ürün sürümü (config.properties applet.version=10.0.1'den).
# CFBundleVersion buna eşitlenir; yayın etiketi <APP_VERSION>_<N> olur.
APP_VERSION="${APP_VERSION:-10.0.1}"

CODEBASE="https://ptt.hs01.kep.tr/download"
JAR_URL="${JAR_URL:-$CODEBASE/$MAIN_JAR}"
CONFIG_URL="$CODEBASE/config.properties"
JAR_FILE="$DOWNLOADS/$MAIN_JAR"
# İkon codebase'de YOK (logo.png 404) → jar içindeki images/logo.png (200x200) çıkarılır.
ICON_PNG="$DOWNLOADS/logo.png"
ICON_IN_JAR="images/logo.png"
ICNS="$BUILD/$ASCII_NAME.icns"

# Gömülecek arm64 Java 11 (runtime). 'jdk' hedefi Azul Zulu 11'i kurar.
JDK11_DEST="$HOME/Library/Java/JavaVirtualMachines/zulu-11-arm64.jdk"
# jpackage için 17+ JDK. 'jpackage-jdk' Zulu 21 kurar.
JDK21_DEST="$HOME/Library/Java/JavaVirtualMachines/zulu-21-arm64.jdk"

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_info() { printf '\033[36m▸\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# Gerçekten istenen major sürüm mü (java_home yanlış sürüm döndürebiliyor)
jhome() {  # $1=major  $2=hedef .jdk
	if [ -x "$2/Contents/Home/bin/java" ]; then echo "$2/Contents/Home"; return 0; fi
	local h; h="$(/usr/libexec/java_home -v "$1" -a arm64 2>/dev/null || true)"
	if [ -n "$h" ] && "$h/bin/java" -version 2>&1 | grep -q "version \"$1"; then echo "$h"; fi
	return 0
}
jdk11_home() { jhome 11 "$JDK11_DEST"; }

find_jpackage() {
	local v jh
	for v in 25 24 23 22 21 20 19 18 17; do
		jh="$(/usr/libexec/java_home -v "$v" -a arm64 2>/dev/null || true)"
		[ -n "$jh" ] && [ -x "$jh/bin/jpackage" ] && { echo "$jh/bin/jpackage"; return 0; }
	done
	local home
	for home in $(/usr/libexec/java_home -V 2>&1 | grep -oE '/[^ ]+/Contents/Home' | sort -u); do
		[ -x "$home/bin/jpackage" ] && { echo "$home/bin/jpackage"; return 0; }
	done
	return 1
}

install_zulu() {  # $1=java_version  $2=hedef .jdk
	c_info "Azul Zulu $1 (aarch64) indiriliyor…"
	local url
	url="$(curl -s "https://api.azul.com/metadata/v1/zulu/packages/?java_version=$1&os=macos&arch=aarch64&archive_type=tar.gz&java_package_type=jdk&javafx_bundled=false&latest=true&release_status=ga&availability_types=CA&page=1&page_size=1" \
		| /usr/bin/python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["download_url"])')"
	[ -n "$url" ] || die "Zulu $1 URL'si alınamadı."
	mkdir -p "$DOWNLOADS"; local tmp="$DOWNLOADS/zulu$1.tgz"
	curl -fSL --retry 5 -o "$tmp" "$url"
	gzip -t "$tmp" 2>/dev/null || die "Zulu $1 indirme bozuk."
	local stage; stage="$(mktemp -d)"; tar xzf "$tmp" -C "$stage"
	local b; b="$(find "$stage" -maxdepth 1 -type d -name 'zulu*' | head -1)"
	[ -n "$b" ] || die "Zulu $1 arşiv yapısı farklı."
	mkdir -p "$(dirname "$2")"; rm -rf "$2"; mv "$b" "$2"; rm -rf "$stage"
}

# ----- Hedefler -----

check_deps() {
	c_info "Ön koşullar denetleniyor…"
	local t
	for t in curl unzip zip codesign plutil sips iconutil shasum; do
		command -v "$t" >/dev/null 2>&1 || die "Gerekli araç yok: $t"
	done
	c_ok "Araçlar mevcut"
	local ok=0
	[ -n "$(jdk11_home)" ] && c_ok "arm64 Java 11 (runtime): $(jdk11_home)" || { c_warn "arm64 Java 11 YOK → scripts/build.sh jdk"; ok=1; }
	if jp="$(find_jpackage)"; then c_ok "jpackage: $jp"; else c_warn "jpackage'lı 17+ JDK YOK → scripts/build.sh jpackage-jdk"; ok=1; fi
	return $ok
}

jdk() {
	[ -n "$(jdk11_home)" ] && { c_ok "arm64 Java 11 zaten kurulu."; return 0; }
	install_zulu 11 "$JDK11_DEST"
	[ -n "$(jdk11_home)" ] && c_ok "Kuruldu: $JDK11_DEST" || die "Java 11 kurulum sonrası görünmüyor."
}

jpackage_jdk() {
	find_jpackage >/dev/null 2>&1 && { c_ok "jpackage zaten var."; return 0; }
	install_zulu 21 "$JDK21_DEST"
	find_jpackage >/dev/null 2>&1 && c_ok "jpackage hazır." || die "jpackage bulunamadı."
}

download() {
	c_info "elektronik-imza.jar indiriliyor (codebase: $CODEBASE)…"
	mkdir -p "$DOWNLOADS" "$BUILD"
	[ -s "$JAR_FILE" ] && c_ok "Önbellekten: $JAR_FILE ($(du -h "$JAR_FILE" | cut -f1))" \
		|| { c_info "İndiriliyor: $JAR_URL"; curl -fL --retry 3 -o "$JAR_FILE" "$JAR_URL"; }
	# Doğrula: main-class + gömülü ikon
	# (içeriği önce değişkene al; grep -q erken çıkıp pipefail'i tetiklemesin)
	local mf list
	mf="$(unzip -p "$JAR_FILE" META-INF/MANIFEST.MF)"
	[[ "$mf" == *"$MAIN_CLASS"* ]] || die "Main-Class bulunamadı (bozuk jar?)."
	list="$(unzip -l "$JAR_FILE")"
	[[ "$list" == *"$ICON_IN_JAR"* ]] || die "İkon ($ICON_IN_JAR) jar'da yok!"
	c_ok "jar doğrulandı (main-class + gömülü ikon mevcut)"
	# İkon codebase'de 404 → jar'dan çıkar.
	[ -s "$ICON_PNG" ] || { c_info "İkon jar'dan çıkarılıyor: $ICON_IN_JAR"; unzip -p "$JAR_FILE" "$ICON_IN_JAR" > "$ICON_PNG"; }
	[ -s "$ICON_PNG" ] || die "İkon çıkarılamadı."
	c_ok "İkon hazır: $ICON_PNG"
}

icns() {
	[ -s "$ICON_PNG" ] || die "Önce 'download' çalıştır (ikon yok)."
	c_info ".icns üretiliyor (jar içi logo.png, 200x200)…"
	mkdir -p "$BUILD"
	local set; set="$BUILD/$ASCII_NAME.iconset"; rm -rf "$set"; mkdir -p "$set"
	# Kaynak 200x200 → 16/32/128 gerçek küçültme; 256+ hafif upscale (tam iconset için)
	local s
	for s in 16 32 128; do
		sips -z "$s" "$s" "$ICON_PNG" --out "$set/icon_${s}x${s}.png" >/dev/null
		local d=$((s*2))
		sips -z "$d" "$d" "$ICON_PNG" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
	done
	sips -z 256 256 "$ICON_PNG" --out "$set/icon_256x256.png" >/dev/null
	sips -z 512 512 "$ICON_PNG" --out "$set/icon_256x256@2x.png" >/dev/null
	sips -z 512 512 "$ICON_PNG" --out "$set/icon_512x512.png" >/dev/null
	iconutil -c icns "$set" -o "$ICNS" || die "iconutil başarısız."
	rm -rf "$set"
	c_ok ".icns üretildi: $ICNS"
}

package() {
	[ -s "$JAR_FILE" ] || die "Önce 'download' çalıştır."
	[ -s "$ICNS" ] || icns
	local jp; jp="$(find_jpackage)" || die "jpackage yok → scripts/build.sh jpackage-jdk"
	local rt; rt="$(jdk11_home)"; [ -n "$rt" ] || die "Java 11 yok → scripts/build.sh jdk"
	[ -f "$rt/lib/jli/libjli.dylib" ] || die "Java 11 runtime layout farklı: $rt"

	c_info "jpackage girdisi hazırlanıyor…"
	local in="$BUILD/_input"; rm -rf "$in"; mkdir -p "$in"
	cp "$JAR_FILE" "$in/"

	c_info "jpackage ile .app paketleniyor (Java 11 gömülü, v$APP_VERSION)…"
	rm -rf "$APP" "$BUILD/$ASCII_NAME.app"
	"$jp" --type app-image --name "$ASCII_NAME" --app-version "$APP_VERSION" \
		--input "$in" --main-jar "$MAIN_JAR" --main-class "$MAIN_CLASS" \
		--runtime-image "$rt" \
		--java-options "-Djnlp.config=$CONFIG_URL" \
		--icon "$ICNS" \
		--mac-package-identifier "$BUNDLE_ID" \
		--dest "$BUILD" 2>&1 | grep -viE 'NoSuchElement|No value' || true
	[ -d "$BUILD/$ASCII_NAME.app" ] || die "jpackage .app üretemedi."

	local plist="$BUILD/$ASCII_NAME.app/Contents/Info.plist"
	plutil -replace CFBundleName -string "$APP_NAME" "$plist"
	plutil -replace CFBundleDisplayName -string "$APP_NAME" "$plist" 2>/dev/null \
		|| plutil -insert CFBundleDisplayName -string "$APP_NAME" "$plist"
	# Retina keskinlik (JEP 263 + bu bayrak)
	plutil -replace NSHighResolutionCapable -bool true "$plist"
	mv "$BUILD/$ASCII_NAME.app" "$APP"
	c_ok "Paketlendi: $APP ($(du -sh "$APP" | cut -f1))"
}

sign() {
	[ -d "$APP" ] || die "Önce 'package' çalıştır."
	c_info "ad-hoc imzalanıyor…"
	find "$APP" -name '._*' -delete 2>/dev/null || true
	codesign --force -s - --identifier "$BUNDLE_ID" "$APP"
	codesign --verify --strict "$APP" 2>/dev/null && c_ok "İmza geçerli (adhoc, strict)" || die "İmza doğrulanamadı."
}

run() {
	[ -d "$APP" ] || die "Önce 'all' çalıştır."
	c_info "Açılıyor: $APP"
	open "$APP"
}

# DMG arka planını assets/dmg-background.svg'den üretir: 1x + 2x PNG → HiDPI tiff.
# (rsvg-convert: brew install librsvg ; tiffutil: macOS yerleşik)
assets() {
	local svg="$ROOT/assets/dmg-background.svg"
	[ -f "$svg" ] || die "Kaynak yok: $svg"
	command -v rsvg-convert >/dev/null || die "rsvg-convert yok → brew install librsvg"
	command -v tiffutil >/dev/null || die "tiffutil yok (macOS yerleşik olmalı)"
	c_info "DMG arka planı üretiliyor (svg → png 1x/2x → tiff)…"
	rsvg-convert -w 660  -h 440 "$svg" -o "$ROOT/assets/dmg-background.png"
	rsvg-convert -w 1320 -h 880 "$svg" -o "$ROOT/assets/dmg-background@2x.png"
	tiffutil -cathidpicheck "$ROOT/assets/dmg-background.png" "$ROOT/assets/dmg-background@2x.png" \
		-out "$ROOT/assets/dmg-background.tiff" >/dev/null
	c_ok "Arka plan: assets/dmg-background.tiff"
}

# Sürükle-bırak yerleşimli .dmg üret (arka plan: assets/dmg-background.tiff).
# İkon konumları arka plandaki boş yuvalarla eşleşir: uygulama (170,220), Applications (490,220).
# DMG_OUT ile çıktı yolu özelleştirilebilir (CI sürüm etiketli ad verir).
dmg() {
	[ -d "$APP" ] || die "Önce 'package' (+ 'sign') çalıştır."
	command -v create-dmg >/dev/null || die "create-dmg yok → brew install create-dmg"
	local bg="$ROOT/assets/dmg-background.tiff"
	[ -f "$bg" ] || assets
	local out="${DMG_OUT:-$BUILD/$ASCII_NAME-arm64.dmg}"
	rm -f "$out"
	c_info "DMG üretiliyor (sürükle-bırak yerleşimi)…"
	create-dmg \
		--volname "$APP_NAME" \
		--background "$bg" \
		--window-pos 200 120 \
		--window-size 660 440 \
		--icon-size 120 \
		--icon "$APP_NAME.app" 170 220 \
		--app-drop-link 490 220 \
		--hide-extension "$APP_NAME.app" \
		--no-internet-enable \
		"$out" "$APP" \
		|| die "create-dmg başarısız."
	[ -f "$out" ] || die "DMG üretilemedi."
	c_ok "DMG: $out ($(du -sh "$out" | cut -f1))"
}

all() {
	check_deps || die "Ön koşul eksik (jdk / jpackage-jdk)."
	download; icns; package; sign
	echo
	c_ok "BİTTİ → $APP"
	c_info "Çalıştır: open \"$APP\"   |   Kur: /Applications'a sürükle"
	c_warn "E-imza ancak gerçek kart + arm64 PKCS#11 middleware (AKİS) ile test edilebilir."
}

clean()     { c_info "build/ temizleniyor…"; rm -rf "$BUILD"; c_ok "temiz"; }
distclean() { c_info "build/ + downloads/ temizleniyor…"; rm -rf "$BUILD" "$DOWNLOADS"; c_ok "temiz"; }

help() {
	cat <<EOF
build.sh — PTT KEP E-İmza native arm64 .app üretici (Java 11 gömülü)

Hedefler:
  all          Tüm hattı çalıştır (varsayılan): download → icns → package → sign
  check-deps   Araç + arm64 Java 11 + jpackage denetimi
  jdk          Gömülecek arm64 Java 11 yoksa Azul Zulu 11 kur
  jpackage-jdk jpackage'lı 17+ JDK yoksa Azul Zulu 21 kur
  download     elektronik-imza.jar indir + doğrula + ikonu jar'dan çıkar
  icns         .icns ikon üret
  package      jpackage ile .app üret (Java 11 gömülü + -Djnlp.config)
  sign         ad-hoc codesign
  run          üretilen .app'i aç
  assets       DMG arka planını svg'den üret (rsvg-convert + tiffutil)
  dmg          sürükle-bırak yerleşimli .dmg üret (create-dmg; DMG_OUT ile ad)
  clean / distclean

Ortam: JAR_URL (kaynak), APP_VERSION (vars: $APP_VERSION)
EOF
}

case "${1:-all}" in
	all) all ;; check-deps) check_deps ;; jdk) jdk ;; jpackage-jdk) jpackage_jdk ;;
	download) download ;; icns) icns ;; package) package ;; sign) sign ;; run) run ;;
	assets) assets ;; dmg) dmg ;;
	clean) clean ;; distclean) distclean ;;
	help|-h|--help) help ;;
	*) die "Bilinmeyen hedef: $1  (scripts/build.sh help)" ;;
esac
```

- [ ] **Step 2: Sözdizimi + help doğrula**

Run: `bash -n scripts/build.sh && bash scripts/build.sh help`
Expected: sözdizimi hatası yok; hedef listesi yazdırılır.

- [ ] **Step 3: check-deps çalıştır**

Run: `bash scripts/build.sh check-deps; echo "exit=$?"`
Expected: Araçlar mevcut ✓; Java 11 / jpackage varsa ✓, yoksa `!` uyarısı + exit=1 (her ikisi de kabul — Task 3'te kurulacak).

- [ ] **Step 4: Commit**

```bash
git add scripts/build.sh
git commit -m "build.sh: PTT KEP arm64 .app build hattı (jnlp.config gömülü, IAIK patch'siz)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Uçtan uca build — make all + .app doğrulama

**Files:**
- Modify: (yalnızca Task 2'de hata çıkarsa `scripts/build.sh`)

**Interfaces:**
- Consumes: Task 2'nin tüm hedefleri.
- Produces: doğrulanmış `build/PTT KEP E-İmza.app` — Task 8'deki kart testinin girdisi.

- [ ] **Step 1: JDK'ları kur**

Run: `make jdk && make jpackage-jdk`
Expected: her ikisi de "zaten kurulu/var" veya indirme sonrası ✓ ile biter.

- [ ] **Step 2: make all**

Run: `make all`
Expected: `download` (jar ~26 MB iner/önbellek, "jar doğrulandı", "İkon hazır") → `icns` → `package` ("Paketlendi: … PTT KEP E-İmza.app") → `sign` ("İmza geçerli") → `BİTTİ`.

- [ ] **Step 3: .app'i doğrula**

Run:
```bash
APP="build/PTT KEP E-İmza.app"
file "$APP/Contents/MacOS/PTTKEPEImza"
codesign --verify --strict "$APP" && echo SIGN_OK
plutil -extract CFBundleName raw "$APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist"
grep -c 'jnlp.config=https://ptt.hs01.kep.tr/download/config.properties' "$APP/Contents/app/PTTKEPEImza.cfg"
"$APP/Contents/runtime/Contents/Home/bin/java" -version 2>&1 | head -1
```
Expected sırasıyla: `Mach-O 64-bit executable arm64`; `SIGN_OK`; `PTT KEP E-İmza`; `10.0.1`; `1` (jnlp.config cfg'de); `openjdk version "11.…`.

- [ ] **Step 4: Açılış smoke testi**

Run: `make run`
Expected: uygulama penceresi açılır ("PTTKEP Webmail E-İmza" arayüzü), çökme yok. Kullanıcıya görsel teyit sorulur; pencere içeriği not edilir (sunucu bağlantı hatası görülürse jnlp.config değeri incelenir). Test sonrası uygulama kapatılır.

- [ ] **Step 5: Commit (yalnızca build.sh değiştiyse)**

```bash
git add scripts/build.sh
git commit -m "build.sh: uçtan uca build sırasında bulunan düzeltmeler

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
(Değişiklik yoksa bu adım atlanır.)

---

### Task 4: kur.sh — tek satır kurulum betiği

**Files:**
- Create: `kur.sh` (chmod +x)

**Interfaces:**
- Consumes: Task 1 Makefile hedefleri (`make jdk`, `make jpackage-jdk`, `make all`).
- Produces: `curl -fsSL https://raw.githubusercontent.com/saidsurucu/pttkep-eimza-mac-arm64/main/kur.sh | bash` akışı; `/Applications/PTT KEP E-İmza.app` kurulumu.

- [ ] **Step 1: kur.sh yaz**

```bash
#!/usr/bin/env bash
# kur.sh — PTT KEP E-İmza'yı Apple Silicon Mac'te tek komutla derleyip kuran yardımcı betik.
#
# README'deki adımları (geliştirici araçları + kaynak kodun indirilmesi +
# Java'ların indirilmesi + derleme + paketleme + Applications'a taşıma) sizin için
# sırayla yapar. Programcı olmanıza gerek yok.
#
# İki şekilde çalışır:
#   • İnternetten tek satırla:
#       curl -fsSL https://raw.githubusercontent.com/saidsurucu/pttkep-eimza-mac-arm64/main/kur.sh | bash
#     (kaynak kodu kendisi indirir, derler ve kurar)
#   • Depoyu zaten indirdiyseniz, klasörün içinde:  ./kur.sh
#
# Asıl derleme mantığı scripts/build.sh içindedir; bu betik onu sarmalar.

set -euo pipefail

REPO_URL="https://github.com/saidsurucu/pttkep-eimza-mac-arm64.git"
CLONE_DIR="$HOME/pttkep-eimza-mac-arm64"

# ----- Renkli, anlaşılır mesajlar -----
if [ -t 1 ]; then
	BOLD=$'\033[1m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
	BOLD=""; GRN=""; YLW=""; RED=""; BLU=""; RST=""
fi
say()  { printf '%s\n' "${BLU}›${RST} $*"; }
ok()   { printf '%s\n' "${GRN}✓${RST} $*"; }
warn() { printf '%s\n' "${YLW}!${RST} $*"; }
die()  { printf '%s\n' "${RED}✗ $*${RST}" >&2; exit 1; }
step() { printf '\n%s\n' "${BOLD}== $* ==${RST}"; }

# ----- Xcode komut satırı araçları (git, make, codesign vb.) -----
# Hem internetten indirme (git) hem derleme (make) için gerekli; bir kez kurulur.
ensure_clt() {
	if xcode-select -p >/dev/null 2>&1; then
		ok "Komut satırı araçları zaten kurulu"
		return
	fi
	warn "Komut satırı araçları yok; kurulum penceresi açılıyor…"
	xcode-select --install >/dev/null 2>&1 || true
	say "Açılan pencerede ${BOLD}\"Yükle\"${RST}ye basıp bitmesini bekleyin."
	say "Kurulum tamamlanınca bu betik kendiliğinden devam edecek…"
	# Kullanıcı kurulumu bitirene kadar bekle (iptal ederse Ctrl+C ile çıkabilir).
	until xcode-select -p >/dev/null 2>&1; do
		printf '.'
		sleep 5
	done
	printf '\n'
	ok "Komut satırı araçları kuruldu"
}

# ----- 0) Ortam kontrolü -----
step "Ortam denetimi"
[ "$(uname -s)" = "Darwin" ] || die "Bu betik yalnızca macOS içindir."
if [ "$(uname -m)" != "arm64" ]; then
	die "Bu betik Apple Silicon (M1/M2/M3/M4) içindir. Mevcut mimari: $(uname -m)"
fi
ok "Apple Silicon Mac algılandı"

# ----- Önyükleme: depo klasörünün içinde miyiz? -----
# curl ... | bash ile çalıştırıldığında BASH_SOURCE boş/geçersiz olur; bu durumda
# kaynak kodu kendimiz indirip oradaki kur.sh'yi yeniden çalıştırırız.
SRC="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [ -n "$SRC" ] && [ -f "$SRC" ]; then
	SCRIPT_DIR="$(cd "$(dirname "$SRC")" && pwd)"
fi

if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/scripts/build.sh" ]; then
	step "Kaynak kodun indirilmesi"
	ensure_clt
	command -v git >/dev/null 2>&1 || die "git bulunamadı (komut satırı araçları eksik olabilir)."
	if [ -d "$CLONE_DIR/.git" ]; then
		say "Depo zaten var, en güncel sürüme güncelleniyor: $CLONE_DIR"
		git -C "$CLONE_DIR" pull --ff-only --quiet || warn "Güncelleme atlandı; mevcut sürümle devam ediliyor."
	else
		[ -e "$CLONE_DIR" ] && die "$CLONE_DIR zaten var ama bir git deposu değil. Lütfen taşıyın/silin."
		say "Kaynak kod indiriliyor: $CLONE_DIR"
		git clone --depth 1 "$REPO_URL" "$CLONE_DIR" --quiet
	fi
	ok "Kaynak kod hazır"
	# İndirilen depodaki kur.sh'yi devral (bu noktadan sonrasını o yürütür).
	exec bash "$CLONE_DIR/kur.sh"
fi

cd "$SCRIPT_DIR"

APP_NAME="PTT KEP E-İmza.app"
BUILT_APP="$SCRIPT_DIR/build/$APP_NAME"
DEST_APP="/Applications/$APP_NAME"

# ----- 1) Xcode komut satırı araçları (make, codesign vb.) -----
step "Geliştirici araçları (bir kez)"
ensure_clt
command -v make >/dev/null 2>&1 || die "make bulunamadı (komut satırı araçları eksik olabilir)."

# ----- 2) Gömülecek arm64 Java 11 -----
step "arm64 Java 11 (gömülecek çalışma zamanı)"
make jdk

# ----- 3) Paketleyici JDK (jpackage'lı 17+) -----
step "Paketleyici JDK (jpackage)"
make jpackage-jdk

# ----- 4) İndir + derle + paketle + imzala -----
step "Derleme + paketleme (birkaç dakika sürebilir)"
make all
[ -d "$BUILT_APP" ] || die "Beklenen uygulama üretilemedi: $BUILT_APP"
ok "Uygulama hazır: $BUILT_APP"

# ----- 5) /Applications'a taşı (gerekirse eskisini değiştir) -----
step "Applications'a kurulum"
if pgrep -f "$APP_NAME/Contents/MacOS" >/dev/null 2>&1; then
	warn "Uygulama açık görünüyor; kapatılıyor…"
	osascript -e 'tell application "PTT KEP E-İmza" to quit' >/dev/null 2>&1 || true
	sleep 2
fi
if [ -e "$DEST_APP" ]; then
	say "Eski sürüm bulundu, değiştiriliyor…"
	rm -rf "$DEST_APP" 2>/dev/null || sudo rm -rf "$DEST_APP"
fi
if mv "$BUILT_APP" "$DEST_APP" 2>/dev/null; then
	ok "Kuruldu: $DEST_APP"
else
	warn "/Applications yazılamadı; yönetici izniyle taşınıyor…"
	sudo mv "$BUILT_APP" "$DEST_APP"
	ok "Kuruldu: $DEST_APP"
fi

# ----- Bitti -----
printf '\n'
ok "${BOLD}BİTTİ.${RST} PTT KEP E-İmza artık Launchpad ve Applications'ta."
say "Açmak için: ${BOLD}open \"$DEST_APP\"${RST}"
printf '\n'
warn "E-imza kullanacaksanız: TÜBİTAK AKİS'in ${BOLD}Apple Silicon (Arm)${RST} sürücüsünü kurun"
say "  https://akiskart.bilgem.tubitak.gov.tr/destek/  → \"Mac OS Arm (Apple Silicon)\""
printf '\n'
say "Yeni sürüm çıktığında bu betiği yeniden çalıştırmanız yeterli (en güncel sürüm otomatik iner)."
```

- [ ] **Step 2: Doğrula**

Run: `chmod +x kur.sh && bash -n kur.sh && grep -c 'pttkep-eimza-mac-arm64' kur.sh`
Expected: sözdizimi hatası yok; grep ≥ 3 (yorum + REPO_URL + CLONE_DIR).
Not: betik tam ÇALIŞTIRILMAZ — çalıştırmak `/Applications`'a kurulum yapar ve `build/` içindeki .app'i taşır (Task 8 kart testi öncesi istenmez).

- [ ] **Step 3: Commit**

```bash
git add kur.sh
git commit -m "kur.sh: tek satır kurulum betiği

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: DMG assets — arka plan SVG + render

**Files:**
- Create: `assets/dmg-background.svg`
- Create (üretilen, commit edilir): `assets/dmg-background.png`, `assets/dmg-background@2x.png`, `assets/dmg-background.tiff`

**Interfaces:**
- Consumes: Task 2 `assets` ve `dmg` hedefleri (yuva merkezleri: uygulama 170,220; Applications 490,220 — create-dmg parametreleriyle eşleşik).
- Produces: `assets/dmg-background.tiff` (dmg hedefinin arka planı).

- [ ] **Step 1: SVG yaz** (edevlet SVG'sinin PTT lacivertine uyarlanmışı; başlık PTT KEP)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
  PTT KEP E-İmza DMG penceresi arka planı (kaynak).
  Render: rsvg-convert ile 1x (660x440) ve 2x (1320x880) PNG → tiffutil HiDPI tiff.
  (Otomatik: scripts/build.sh assets)
  İkonlar (uygulama + Applications) Finder tarafından bunun ÜZERİNE yerleştirilir;
  bu yüzden ikon yuvaları boş bırakılır, yalnızca ok + metin çizilir.
  Yuva merkezleri (create-dmg ile eşleşmeli): uygulama (170,220), Applications (490,220).
-->
<svg width="660" height="440" viewBox="0 0 660 440" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0"  stop-color="#f7f8fa"/>
      <stop offset="1"  stop-color="#eceef2"/>
    </linearGradient>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="1" stdDeviation="2" flood-color="#1f2a44" flood-opacity="0.18"/>
    </filter>
  </defs>

  <!-- zemin -->
  <rect x="0" y="0" width="660" height="440" fill="url(#bg)"/>

  <!-- başlık -->
  <text x="330" y="74" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="26" font-weight="700" fill="#1a2f5e">PTT KEP E-İmza</text>
  <text x="330" y="104" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="14" font-weight="400" fill="#5b6b86">Apple Silicon (arm64) — native</text>

  <!-- ikon yuvaları (boş daireler, Finder ikonları üstüne koyacak) -->
  <circle cx="170" cy="220" r="74" fill="#ffffff" fill-opacity="0.55" stroke="#cdd7e6" stroke-width="1.5"/>
  <circle cx="490" cy="220" r="74" fill="#ffffff" fill-opacity="0.55" stroke="#cdd7e6" stroke-width="1.5"/>

  <!-- sürükleme oku (PTT lacivert) -->
  <g filter="url(#soft)">
    <line x1="260" y1="220" x2="392" y2="220" stroke="#1a2f5e" stroke-width="12" stroke-linecap="round"/>
    <path d="M 386 198 L 420 220 L 386 242 Z" fill="#1a2f5e"/>
  </g>

  <!-- alt yönerge -->
  <text x="330" y="360" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="17" font-weight="600" fill="#1a2f5e">Kurmak için sürükleyin</text>
  <text x="330" y="386" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="13" font-weight="400" fill="#5b6b86">Uygulamayı Applications klasörüne bırakın</text>
</svg>
```

- [ ] **Step 2: Render + doğrula**

Run:
```bash
command -v rsvg-convert >/dev/null || brew install librsvg
make assets
sips -g pixelWidth -g pixelHeight assets/dmg-background.png assets/dmg-background@2x.png
```
Expected: 660×440 ve 1320×880; `assets/dmg-background.tiff` oluşur.

- [ ] **Step 3: (opsiyonel) DMG smoke**

Run: `command -v create-dmg >/dev/null && make dmg || echo "create-dmg yok, atlandı"`
Expected: create-dmg kuruluysa `build/PTTKEPEImza-arm64.dmg` üretilir; değilse atlanır (CI'da zaten test edilecek).

- [ ] **Step 4: Commit**

```bash
git add assets/
git commit -m "DMG arka planı: PTT KEP uyarlaması (svg + render)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: CI — .github/workflows/release.yml

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `make jdk / jpackage-jdk / all / dmg`, `DMG_OUT` env (Task 2), CFBundleVersion=10.0.1 (etiket `10.0.1_N`).

- [ ] **Step 1: release.yml yaz**

```yaml
name: Release (arm64 .app)

# Elle tetiklenir. macOS arm64 runner'da native .app üretir, sürümü
# <APP_VERSION>_<N> olarak etiketler (ör. 10.0.1_1). <N> her yeniden
# yayında (aynı APP_VERSION için) otomatik artar.
on:
  workflow_dispatch:
    inputs:
      app_version:
        description: 'Ürün sürümü (boşsa build.sh varsayılanı = 10.0.1)'
        required: false
      revision:
        description: 'Revizyon numarası (boşsa otomatik = mevcut + 1)'
        required: false
      jar_url:
        description: 'elektronik-imza.jar URL (boşsa codebase varsayılanı)'
        required: false

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-14   # Apple Silicon (arm64) runner
    steps:
      - uses: actions/checkout@v4

      - name: Mimari doğrula (arm64 olmalı)
        run: test "$(uname -m)" = "arm64" || { echo "Runner arm64 değil!"; exit 1; }

      - name: Gömülecek arm64 Java 11 kur (Azul Zulu)
        run: make jdk

      - name: jpackage'lı 17+ JDK hazırla
        run: make jpackage-jdk

      - name: Native arm64 .app üret
        env:
          APP_VERSION: ${{ github.event.inputs.app_version }}
          JAR_URL: ${{ github.event.inputs.jar_url }}
        run: make all

      - name: Mimariyi ve imzayı doğrula
        run: |
          APP="build/PTT KEP E-İmza.app"
          file "$APP/Contents/MacOS/PTTKEPEImza" | grep -q arm64 || { echo "Launcher arm64 değil!"; exit 1; }
          codesign --verify --strict "$APP"

      - name: Sürümü belirle (<APP_VERSION>_<N>)
        id: ver
        env:
          GH_TOKEN: ${{ github.token }}
          INPUT_REV: ${{ github.event.inputs.revision }}
        run: |
          APP_VER=$(plutil -extract CFBundleVersion raw "build/PTT KEP E-İmza.app/Contents/Info.plist")
          echo "Ürün sürümü: $APP_VER"
          if [ -n "$INPUT_REV" ]; then
            REV="$INPUT_REV"
          else
            LAST=$(gh api "repos/${{ github.repository }}/releases" --paginate --jq '.[].tag_name' 2>/dev/null \
              | grep "^${APP_VER}_" | sed "s/^${APP_VER}_//" | sort -n | tail -1)
            REV=$(( ${LAST:-0} + 1 ))
          fi
          TAG="${APP_VER}_${REV}"
          echo "Yayın etiketi: $TAG"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"

      - name: DMG üret (sürükle-bırak yerleşimli)
        env:
          DMG_OUT: ${{ github.workspace }}/PTTKEPEImza-${{ steps.ver.outputs.tag }}-arm64.dmg
        run: |
          brew list create-dmg >/dev/null 2>&1 || brew install create-dmg
          make dmg

      - name: GitHub Release oluştur + dosyayı ekle
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.ver.outputs.tag }}
          name: ${{ steps.ver.outputs.tag }}
          files: PTTKEPEImza-${{ steps.ver.outputs.tag }}-arm64.dmg
          body: |
            Native Apple Silicon (arm64) PTT KEP E-İmza build — Rosetta gerektirmez.
            Java gömülü gelir; ayrıca bir şey kurmaya gerek yok.

            ## Kurulum
            1. Aşağıdaki **`.dmg` dosyasını indirip** çift tıklayın; bir pencere açılır.
            2. Açılan pencerede **`PTT KEP E-İmza`** simgesini, ortadaki okun gösterdiği gibi
               yanındaki **Applications** klasörünün üzerine **sürükleyin**.
            3. İlk açılışta macOS **"geliştirici doğrulanamadı"** diyebilir. Bunu bir kez aşmak için:
               1. **Terminal** uygulamasını açın: `Command (⌘) + Boşluk`'a basın, **Terminal** yazıp **Enter**'a basın.
               2. Şu satırı kopyalayın, Terminal'e yapıştırıp **Enter**'a basın:
                  ```
                  xattr -dr com.apple.quarantine "/Applications/PTT KEP E-İmza.app"
                  ```
               3. Komut bir şey yazmadan biter (normaldir). Artık uygulamayı çift tıklayarak açabilirsiniz.

            ## Not
            - ⚠️ **arm64 AKİS sürücüsü ŞART:** sistemde **Apple Silicon (arm64) AKİS** PKCS#11
              modülü kurulu olmalıdır (Intel-only sürücü arm64 uygulamaya yüklenmez). Kurulum
              için README'deki "Apple Silicon AKİS sürücüsü kurulumu" bölümüne bakın.
```

- [ ] **Step 2: YAML doğrula**

Run: `/usr/bin/python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"`
Expected: `YAML OK` (python3'te yaml yoksa: `ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml'); puts 'YAML OK'"`).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "CI: macos-14 arm64 build + DMG release workflow (elle tetik)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: README.md

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: kur.sh tek satırı (Task 4), make hedefleri (Task 2), CI (Task 6).

- [ ] **Step 1: README.md yaz** (edevlet README yapısı birebir; kartla doğrulama iddiası Task 8 sonucuna bırakıldı — aşağıdaki metinde "henüz doğrulanmadı" satırı var, Task 8 başarılıysa güncellenecek)

```markdown
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

> ⚠️ Gerçek kartla imzalama akışı **henüz doğrulanmadı** (uygulama açılışı
> doğrulandı). Sonuçlar test edildikçe bu not güncellenecektir.

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
  jar'da native kütüphane taşınmaz. Bu yüzden e-Devlet paketleyicisindeki
  Javassist connect-fix patch'i burada gerekmez. AKİS middleware'inin arm64
  sürümü sistemde kurulu olmalıdır.
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
| sürüm | `10.0.1` (config.properties `applet.version`) |
| ikon | jar içi `images/logo.png` → `.icns` |

---

## CI build (isteğe bağlı)

`.github/workflows/release.yml` elle tetiklenir (`workflow_dispatch`):
macos-14 (arm64) runner'da `.app` üretir, mimariyi+imzayı doğrular ve
`<APP_VERSION>_<N>` etiketli bir yayın oluşturur.
```

- [ ] **Step 2: Doğrula**

Run: `grep -c 'pttkep-eimza-mac-arm64\|ptt.hs01.kep.tr' README.md`
Expected: ≥ 5; ayrıca göz kontrolü — edevlet README bölüm sırasıyla eşleşiyor.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "README: kurulum + teknik ayrıntı (edevlet yapısıyla birebir)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Gerçek kart testi (kullanıcı) + iddiaların güncellenmesi

**Files:**
- Modify: `README.md` (test sonucuna göre)
- Modify: `.github/workflows/release.yml` (test sonucuna göre release body'ye doğrulama notu)

**Interfaces:**
- Consumes: Task 3'ün doğrulanmış `.app`'i.

Bu görev bir **checkpoint**: kullanıcı gerçek AKİS kart + arm64 AKİS sürücüsüyle
akışı dener: `.app` aç → kart algılama → sertifika listesi → PIN → imza →
PTT KEP webmail'de işlem doğrulama.

- [ ] **Step 1: Kullanıcıdan test iste**

`make run` ile uygulamayı aç; kullanıcıya test akışını bildir ve sonucu bekle.

- [ ] **Step 2a: BAŞARILI ise — README güncelle**

`README.md`'de şu bloğu:

```markdown
> ⚠️ Gerçek kartla imzalama akışı **henüz doğrulanmadı** (uygulama açılışı
> doğrulandı). Sonuçlar test edildikçe bu not güncellenecektir.
```

şununla değiştir:

```markdown
> ✅ Apple Silicon'da **gerçek kartla tam imzalama** (sertifika → PIN → imza)
> doğrulandı. (Tek bir kurulumda test edildi; yine de farklı kart/sürücü
> sürümlerinde değişiklik olabilir.)
```

ve `.github/workflows/release.yml` release body'sindeki `## Not` listesine şu maddeyi ekle:

```yaml
            - ✅ Apple Silicon'da gerçek kartla **tam imzalama** (sertifika → PIN → imza)
              doğrulandı.
```

Commit:
```bash
git add README.md .github/workflows/release.yml
git commit -m "Gerçek kartla imzalama doğrulandı; README + release notu güncellendi

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 2b: BAŞARISIZ ise — superpowers:systematic-debugging ile kök neden**

Bilinen risk sırası (spec'ten):
1. **`beginExclusive`/CryptoTokenKit çakışması** — belirti: kart takılıyken
   `SCARD_E_READER_UNAVAILABLE` / kart görünmüyor. Çözüm şablonu:
   adalet-eimza-mac-arm64 reposundaki `-javaagent` yaklaşımı (beginExclusive
   no-op) bu repoya `scripts/` altına uyarlanır ve jpackage
   `--java-options`'a eklenir.
2. **sqlite arm64 native yok** — belirti: `UnsatisfiedLinkError`/sqlite hatası.
   Çözüm şablonu: ude-mac-arm repodaki native-swap (modern xerial sqlite-jdbc
   arm64 jnilib'ini jar içine yerleştirme) `package` adımına eklenir.
3. **TLS/sertifika hatası** — belirti: sunucu bağlantı hatası. Config'te
   `ssl_check=false` mevcut; gerekirse `--java-options`'a ilgili bayrak eklenir.
Her düzeltme ayrı commit; düzeltme sonrası Step 1'e dön.

- [ ] **Step 3: Eski klasörü temizle (kullanıcı onayıyla)**

`/Users/saidsurucu/Documents/GitHub/pttkep-eimza-mac` (yalnızca eski JNLP içerir;
JNLP kopyası yeni repoda mevcut) kullanıcı onayı sonrası silinir.

---

## Doğrulama Özeti (plan self-review yapıldı)

- Spec kapsaması: repo yapısı (T1,T4,T5,T6,T7), build.sh tasarımı (T2), uçtan uca
  build+`.app` doğrulama (T3), kur.sh (T4), README (T7), CI (T6), test planı +
  riskler (T8), kapsam dışılar korunuyor. ✓
- Spec'in "CI: paket dağıtımı yok" cümlesi, edevlet'in fiilî workflow'una
  (elle tetiklenen release + DMG) uyarlandı — "birebir aynı mantık" gereği
  workflow release üretebilir; tetiklemek kullanıcının kararıdır. Spec bu yönde
  güncellenecek (T6 commit'inde).
- Placeholder taraması: tüm dosya içerikleri tam; TBD/TODO yok. ✓
- Ad/tip tutarlılığı: `PTTKEPEImza`, `PTT KEP E-İmza`, hedef adları, DMG yolları
  görevler arası birebir aynı. ✓
```
