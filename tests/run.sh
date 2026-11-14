#!/usr/bin/env bash
# tests/run.sh — 휴대폰 없이 도구 전체를 시험한다.
#
#   bash tests/run.sh
#
# 필요: bash, python3 + mutagen, ffmpeg(libmp3lame). termux-saf-* 는 tests/mock 의 가짜를 쓴다
# (임시 폴더 하나를 SD 카드의 Asmr 폴더처럼 보여 줌). 실제 SD 카드나 네트워크는 쓰지 않는다.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/asmr-tools-test.XXXXXX")"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT; [ -n "${KEEP:-}" ] && echo "작업 폴더: $WORK"

# HOME 을 바꾸기 전에 pip --user 로 설치한 모듈(mutagen) 위치를 붙잡아 둔다
PYTHONUSERBASE="$(python3 -m site --user-base 2>/dev/null)" && export PYTHONUSERBASE
export HOME="$WORK/home"
export ASMR_COVER_HOME="$WORK/state"
export PATH="$REPO/tests/mock:$PATH"
export SAF_ROOT_URI="content://mock/tree/0000-0000%3AAsmr"
mkdir -p "$HOME"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
section() { printf '\n== %s\n' "$1"; }

FF=(ffmpeg -nostdin -loglevel error -y)
tone()  { mkdir -p "$(dirname "$1")"; "${FF[@]}" -f lavfi -i "sine=f=${3:-440}:d=${2:-3}" "${@:4}" "$1"; }
image() { mkdir -p "$(dirname "$1")"; "${FF[@]}" -f lavfi -i "testsrc=s=$2" -frames:v 1 "$1"; }
spec()  { ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,bit_rate,sample_rate,channels \
              -of csv=p=0 "$1"; }
cover() { ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$1"; }
pics()  { python3 -c 'import sys; from mutagen.mp3 import MP3; t=MP3(sys.argv[1]).tags; print(len(t.getall("APIC")) if t else 0)' "$1"; }
sum()   { md5sum "$1" | cut -d' ' -f1; }

for c in ffmpeg ffprobe python3; do command -v "$c" >/dev/null || { echo "필요: $c"; exit 2; }; done
python3 -c 'import mutagen' 2>/dev/null || { echo "필요: pip install mutagen"; exit 2; }

CONVERT="$REPO/snow_convert_final_v3.sh"
UPDATE="$REPO/asmr_cover_update.sh"
EMBED="$REPO/asmr_cover_embed.sh"

# ------------------------------------------------------------------ 변환
section "snow_convert_final_v3.sh"
M="$WORK/moving"
tone "$M/W1/01 トラック.wav" 4 440 -ar 48000 -ac 1
image "$M/W1/cover.jpg" 1200x800
tone "$M/W2/a.flac" 3 300 -c:a flac
tone "$M/W2/a.wav" 3 300
tone "$M/W2/ok.mp3" 3 500 -c:a libmp3lame -b:a 320k -ar 44100 -ac 2
tone "$M/W2/low.mp3" 3 600 -c:a libmp3lame -b:a 128k -ar 48000 -ac 1
"${FF[@]}" -f lavfi -i testsrc=s=320x240:d=3 -f lavfi -i "sine=f=200:d=3" -f lavfi -i "sine=f=900:d=3" \
    -map 0 -map 1 -map 2 -c:v mpeg4 -c:a aac -shortest "$M/W2/vid.mp4"
image "$M/W2/art.png" 600x900
tone "$M/W3/특수 '문자' & \$x.m4a" 3 700 -c:a aac
head -c 4000 /dev/urandom > "$M/W3/bad.flac"
cp "$M/W2/ok.mp3" "$M/W2/.snow_v2_tmp.mp3"
before="$(cd "$M" && find . -type f -exec md5sum {} + | sort)"

bash "$CONVERT" --dir "$M" > "$WORK/conv_dry.log" 2>&1
check "미리보기는 파일을 바꾸지 않는다" test "$before" = "$(cd "$M" && find . -type f -exec md5sum {} + | sort)"
check "미리보기 통계: 대상 8, 예정 5, 건너뜀 1, 충돌 1, 실패 1" \
    grep -qzE '전체 대상 파일 : 8.*변환 예정 파일 : 5.*건너뛴 파일    : 1.*이름 충돌 파일 : 1.*실패 파일      : 1' "$WORK/conv_dry.log"

bash "$CONVERT" --dir "$M" --apply > "$WORK/conv.log" 2>&1
check "실패가 있으면 종료 코드가 0이 아니다" test $? -ne 0
for f in "W1/01 トラック.mp3" W2/a.mp3 W2/low.mp3 W2/vid.mp3 "W3/특수 '문자' & \$x.mp3"; do
    check "규격 320k/44.1k/2ch: $f" test "$(spec "$M/$f")" = "mp3,44100,2,320000"
done
check "변환된 원본은 삭제" test ! -e "$M/W1/01 トラック.wav" -a ! -e "$M/W2/vid.mp4"
check "이름 충돌한 a.wav 는 그대로" test -f "$M/W2/a.wav"
check "읽을 수 없는 파일은 그대로" test -f "$M/W3/bad.flac"
check "재인코딩 백업은 남지 않음" test -z "$(find "$M" -name '*.snow_v3_backup_*')"
check "임시 파일이 남지 않음" test -z "$(find "$M" -name '.snow_v3_tmp_*')"
check ".snow_v2_ 파일은 건드리지 않음" test -f "$M/W2/.snow_v2_tmp.mp3"
check "썸네일 단계: 이미지 1장 작품에 240x240 커버" test "$(cover "$M/W1/01 トラック.mp3")" = "240,240"
check "썸네일 단계: 이미지 없는 작품은 커버 없음" test "$(pics "$M/W3/특수 '문자' & \$x.mp3")" = 0

I="$WORK/interrupt"
tone "$I/W/long.wav" 600 440
s0="$(sum "$I/W/long.wav")"
python3 - "$CONVERT" "$I" <<'EOF'
import os, signal, subprocess, sys, time
p = subprocess.Popen(["bash", sys.argv[1], "--dir", sys.argv[2], "--apply", "--no-cover"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
time.sleep(2)
os.killpg(p.pid, signal.SIGINT)
sys.exit(0 if p.wait() == 130 else 1)
EOF
check "Ctrl+C: 종료 코드 130" test $? -eq 0
check "Ctrl+C: 원본 그대로" test "$(sum "$I/W/long.wav")" = "$s0"
check "Ctrl+C: 임시·결과 파일 없음" test "$(ls -A "$I/W")" = "long.wav"

# ------------------------------------------------------------------ 썸네일 (SAF)
section "asmr_cover_embed.sh / asmr_cover_update.sh (SAF)"
export MOCK_SAF_BASE="$WORK/sd"
SD="$MOCK_SAF_BASE"
tone "$SD/A/mp3/01.mp3" 2 300 -c:a libmp3lame
tone "$SD/A/mp3/02.mp3" 2 310 -c:a libmp3lame
image "$SD/A/jacket/01.jpg" 1200x800
image "$SD/A/jacket/02.jpg" 500x500
tone "$SD/B/x.mp3" 2 320 -c:a libmp3lame
image "$SD/B/one.jpg" 300x300
image "$SD/B/two.jpg" 300x300
tone "$SD/C/c.mp3" 2 330 -c:a libmp3lame
image "$SD/C/표지.png" 1280x720
tone "$SD/D/has.mp3" 2 340 -c:a libmp3lame
image "$SD/D/d.jpg" 300x300
python3 - "$SD/D/has.mp3" "$SD/D/d.jpg" <<'EOF'
import sys
from mutagen.mp3 import MP3
from mutagen.id3 import APIC
a = MP3(sys.argv[1]); a.tags.add(APIC(encoding=0, mime="image/jpeg", type=3, desc="", data=open(sys.argv[2], "rb").read())); a.save()
EOF
tone "$SD/root.mp3" 2 350 -c:a libmp3lame
has0="$(sum "$SD/D/has.mp3")"
b0="$(sum "$SD/B/x.mp3")"

bash "$EMBED" > "$WORK/emb_dry.log" 2>&1
check "기본 규칙: 이름 일치 2곡만 대상" grep -q '처리 대상 수            : 2' "$WORK/emb_dry.log"
check "다른 작품의 이미지는 후보가 아님" test "$(pics "$SD/C/c.mp3")" = 0

MOCK_SAF_NO_TRUNC=1 bash "$EMBED" --apply --yes > "$WORK/emb_notrunc.log" 2>&1
check "덮어쓰기가 truncate 되지 않는 기기에서는 적용 중단" grep -q '적용을 중단' "$WORK/emb_notrunc.log"
check "중단 시 파일 변화 없음" test "$(pics "$SD/A/mp3/01.mp3")" = 0

printf 'y\n' | bash "$UPDATE" > "$WORK/upd.log" 2>&1
check "update: 이름 일치 + 대표 커버 + PNG" test "$(cover "$SD/A/mp3/01.mp3")" = "240,240" -a "$(cover "$SD/C/c.mp3")" = "240,240"
check "update: 이미지 여러 장인 작품은 적용 안 함" test "$(sum "$SD/B/x.mp3")" = "$b0"
check "update: 이미지 여러 장 후보를 보여 줌" grep -q 'one.jpg' "$WORK/upd.log"
check "update: 기존 커버가 있는 곡은 그대로" test "$(sum "$SD/D/has.mp3")" = "$has0"
check "작품 폴더 밖 MP3 는 그대로" test "$(pics "$SD/root.mp3")" = 0

bash "$EMBED" --replace --work C > "$WORK/rep_dry.log" 2>&1
printf 'y\n' | bash "$UPDATE" --replace > "$WORK/rep_nowork.log" 2>&1
check "--replace 는 --work 없이 거부" grep -q -- '--work 로 바꿀 작품을 지정' "$WORK/rep_nowork.log"
image "$SD/D/d.jpg" 640x200
printf 'y\n' | bash "$UPDATE" --replace --work D > "$WORK/rep.log" 2>&1
check "--replace: 커버가 1개로 교체" test "$(pics "$SD/D/has.mp3")" = 1 -a "$(sum "$SD/D/has.mp3")" != "$has0"

# ------------------------------------------------------------------ 로컬 폴더
section "--local-dir"
L="$WORK/local"
tone "$L/W/sub/01_耳かき.mp3" 2 300 -c:a libmp3lame
image "$L/W/c.webp" 400x400 2>/dev/null || image "$L/W/c.png" 400x400
printf 'y\n' | bash "$UPDATE" --local-dir "$L" > "$WORK/loc.log" 2>&1
check "로컬 폴더 커버 (WEBP/PNG)" test "$(cover "$L/W/sub/01_耳かき.mp3")" = "240,240"
check "로컬 폴더에 임시 파일이 남지 않음" test -z "$(find "$L" -name '*.coverembed.tmp')"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
