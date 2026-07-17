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
# Görünen ürün sürümü (uygulama pencere başlığından doğrulandı: "PTTKEP Webmail
# E-İmza v1.2.5"; config.properties'teki applet.version=10.0.1 ürün sürümü değil,
# applet protokol sürümüdür). CFBundleVersion buna eşitlenir; yayın etiketi
# <APP_VERSION>_<N> olur.
APP_VERSION="${APP_VERSION:-1.2.5}"

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
