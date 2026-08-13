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

# ----- "sudo ./kur.sh" ile başlatıldıysa normal kullanıcıya dön -----
# Root olarak yazılan kaynak kod/önbellek kullanıcının ev dizininde root'a ait
# kalır ve sonraki (sudo'suz) kurulum "Permission denied" ile düşer. Yönetici
# izni yalnızca /Applications adımında, gerektiği anda isteniyor.
if [ "$(id -u)" = "0" ]; then
	SRC0="${BASH_SOURCE[0]:-}"
	if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ -f "$SRC0" ]; then
		warn "Kurulum 'sudo' ile başlatıldı; normal kullanıcı ($SUDO_USER) olarak devam ediliyor."
		exec sudo -u "$SUDO_USER" -H /bin/bash "$(cd "$(dirname "$SRC0")" && pwd)/$(basename "$SRC0")"
	fi
	die "Bu kurulumu 'sudo' ile çalıştırmayın. Normal kullanıcı olarak: ./kur.sh"
fi

# ----- 0) Ortam kontrolü -----
step "Ortam denetimi"
[ "$(uname -s)" = "Darwin" ] || die "Bu betik yalnızca macOS içindir."
# Donanım Apple Silicon olsa bile Terminal x86_64 (Rosetta) modunda açılmış
# olabilir — o zaman `uname -m` x86_64 döner ve arm64 çalışma zamanı üretilemez.
# Donanım gerçekten arm64 ise betiği arm64 olarak yeniden başlatıyoruz.
ARCH_SWITCH=0
if [ "$(uname -m)" != "arm64" ]; then
	if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = "1" ] \
	   && [ "${KUR_ARCH_SWITCHED:-0}" != "1" ] && command -v arch >/dev/null 2>&1; then
		warn "Terminal Rosetta (x86_64) modunda; otomatik olarak arm64'e geçilecek."
		ARCH_SWITCH=1
	else
		die "Bu betik Apple Silicon (M1/M2/M3/M4) içindir. Mevcut mimari: $(uname -m)"
	fi
else
	ok "Apple Silicon Mac algılandı"
fi

# Rosetta terminalinde başlatıldıysak betiği arm64 olarak yeniden başlatırız.
# (Hemen yapamıyoruz: "curl | bash" ile çalıştırıldığında yeniden başlatılacak
#  bir dosya henüz diskte yok — kaynak kod indikten sonra çağrılıyor.)
reexec_arm64() {
	say "arm64 mimarisine geçiliyor…"
	export KUR_ARCH_SWITCHED=1
	exec arch -arm64 /bin/bash "$1"
}

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
	if [ "$ARCH_SWITCH" = "1" ]; then reexec_arm64 "$CLONE_DIR/kur.sh"; fi
	exec bash "$CLONE_DIR/kur.sh"
fi

cd "$SCRIPT_DIR"

# Kaynak kod diskte; Rosetta terminalinden geldiysek burada arm64'e geçiyoruz.
if [ "$ARCH_SWITCH" = "1" ]; then reexec_arm64 "$SCRIPT_DIR/kur.sh"; fi

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
