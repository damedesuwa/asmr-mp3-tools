#!/usr/bin/env bash
# tests/run.sh — 휴대폰 없이 asmr_mp3.sh 를 시험한다.
#
#   bash tests/run.sh
#
# 필요: bash, python3 + mutagen (커버 개수 확인용), ffmpeg(libmp3lame). 임시 폴더만 쓴다.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/asmr-tools-test.XXXXXX")"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT; [ -n "${KEEP:-}" ] && echo "작업 폴더: $WORK"

# HOME 을 바꾸기 전에 pip --user 로 설치한 모듈(mutagen) 위치를 붙잡아 둔다
PYTHONUSERBASE="$(python3 -m site --user-base 2>/dev/null)" && export PYTHONUSERBASE
export HOME="$WORK/home"
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

MP3="$REPO/asmr_mp3.sh"

# ------------------------------------------------------------------ asmr_mp3.sh (변환 + 커버)
section "asmr_mp3.sh"
M="$WORK/moving"
tone "$M/W1/mp3/01 トラック.wav" 4 440 -ar 48000 -ac 1
image "$M/W1/cover.jpg" 1200x800
tone "$M/W2/a.flac" 3 300 -c:a flac
tone "$M/W2/a.wav" 3 300
tone "$M/W2/ok.mp3" 3 500 -c:a libmp3lame -b:a 320k -ar 44100 -ac 2 -metadata title=제목 -metadata track=7
tone "$M/W2/low.mp3" 3 600 -c:a libmp3lame -b:a 128k -ar 48000 -ac 1
"${FF[@]}" -f lavfi -i testsrc=s=320x240:d=3 -f lavfi -i "sine=f=200:d=3" -f lavfi -i "sine=f=900:d=3" \
    -map 0 -map 1 -map 2 -c:v mpeg4 -c:a aac -shortest "$M/W2/vid.mp4"
image "$M/W2/one.jpg" 500x500
image "$M/W2/two.png" 600x900
tone "$M/W3/특수 '문자' & \$x.m4a" 3 700 -c:a aac
head -c 4000 /dev/urandom > "$M/W3/bad.flac"
tone "$M/root.wav" 2 800
cp "$M/W2/ok.mp3" "$M/W2/.snow_v2_tmp.mp3"
before="$(cd "$M" && find . -type f -exec md5sum {} + | sort)"
audio_md5() { ffmpeg -nostdin -v error -i "$1" -map 0:a -c copy -f md5 -; }
ok_audio="$(audio_md5 "$M/W2/ok.mp3")"

bash "$MP3" --dir "$M" </dev/null > "$WORK/mp3_dry.log" 2>&1
check "미리보기는 파일을 바꾸지 않는다" test "$before" = "$(cd "$M" && find . -type f -exec md5sum {} + | sort)"
check "미리보기: 이미지 여러 장 작품을 알려 줌" grep -q 'two.png' "$WORK/mp3_dry.log"
# 미리보기에서는 여러 장인 W2 의 커버가 아직 정해지지 않으므로 규격 MP3(ok.mp3)는 건너뜀
check "미리보기 통계: 대상 9, 예정 6, 건너뜀 1, 충돌 1, 실패 1" \
    grep -qzE '전체 대상 파일 : 9.*변환 예정      : 6.*커버만 추가    : 0.*건너뜀         : 1.*이름 충돌      : 1.*실패           : 1' "$WORK/mp3_dry.log"

printf '2\n' | bash "$MP3" --dir "$M" --apply > "$WORK/mp3.log" 2>&1
check "실패가 있으면 종료 코드가 0이 아니다" test "${PIPESTATUS[1]}" -ne 0
for f in "W1/mp3/01 トラック.mp3" W2/a.mp3 W2/low.mp3 W2/vid.mp3 W2/ok.mp3 "W3/특수 '문자' & \$x.mp3" root.mp3; do
    check "규격 320k/44.1k/2ch: $f" test "$(spec "$M/$f")" = "mp3,44100,2,320000"
done
check "이미지 1장 작품: 하위 폴더 곡에도 커버" test "$(cover "$M/W1/mp3/01 トラック.mp3")" = "240,240"
check "여러 장 중 고른 번호(2)로 커버" grep -q '커버: two.png' "$WORK/mp3.log"
check "고른 커버가 들어감 (1개)" test "$(cover "$M/W2/a.mp3")" = "240,240" -a "$(pics "$M/W2/vid.mp3")" = 1
check "규격 MP3 는 오디오 그대로 커버만" test "$(audio_md5 "$M/W2/ok.mp3")" = "$ok_audio" -a "$(pics "$M/W2/ok.mp3")" = 1
check "규격 MP3 의 기존 태그 유지" test "$(ffprobe -v error -show_entries format_tags=title -of csv=p=0 "$M/W2/ok.mp3")" = "제목"
check "이미지 없는 작품·폴더 밖 파일은 커버 없음" test "$(pics "$M/W3/특수 '문자' & \$x.mp3")" = 0 -a "$(pics "$M/root.mp3")" = 0
check "변환된 원본은 삭제" test ! -e "$M/W1/mp3/01 トラック.wav" -a ! -e "$M/W2/vid.mp4"
check "이름 충돌한 a.wav 는 그대로" test -f "$M/W2/a.wav"
check "읽을 수 없는 파일은 그대로" test -f "$M/W3/bad.flac"
check "원본 이미지는 그대로" test -f "$M/W1/cover.jpg" -a -f "$M/W2/one.jpg"
check "백업·임시 파일이 남지 않음" test -z "$(find "$M" -name '*.snow_v3_*')"
check ".snow_v2_ 파일은 건드리지 않음" test -f "$M/W2/.snow_v2_tmp.mp3"

printf '2\n' | bash "$MP3" --dir "$M" --apply > "$WORK/mp3_again.log" 2>&1
check "다시 돌리면 바꿀 것이 없음" grep -qzE '변환 완료      : 0.*커버만 추가    : 0' "$WORK/mp3_again.log"
w1="$(sum "$M/W1/mp3/01 トラック.mp3")"
image "$M/W1/cover.jpg" 300x900
bash "$MP3" --dir "$M" --apply --replace </dev/null > "$WORK/mp3_rep.log" 2>&1
check "--replace: 커버가 바뀌고 1개만" test "$(sum "$M/W1/mp3/01 トラック.mp3")" != "$w1" -a "$(pics "$M/W1/mp3/01 トラック.mp3")" = 1

I="$WORK/interrupt"
tone "$I/W/long.wav" 600 440
image "$I/W/c.jpg" 300x300
s0="$(sum "$I/W/long.wav")"
python3 -c '
import os, signal, subprocess, sys, time
p = subprocess.Popen(["bash", sys.argv[1], "--dir", sys.argv[2], "--apply"], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
time.sleep(3)
os.killpg(p.pid, signal.SIGINT)
sys.exit(0 if p.wait() == 130 else 1)
' "$MP3" "$I"
check "Ctrl+C: 종료 코드 130" test $? -eq 0
check "Ctrl+C: 원본 그대로" test "$(sum "$I/W/long.wav")" = "$s0"
check "Ctrl+C: 임시·결과 파일 없음" test "$(ls -A "$I/W" | tr '\n' ' ')" = "c.jpg long.wav "

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
