#!/usr/bin/env bash
# asmr_mp3.sh — 폴더 하나를 MP3 320 kbps / 44.1 kHz / Stereo 로 통일하고, 작품마다 240x240 커버까지 넣는다.
#
#   bash asmr_mp3.sh              미리보기 (아무것도 바꾸지 않음)
#   bash asmr_mp3.sh --apply      실제 적용
#   bash asmr_mp3.sh --help       도움말
#   --dir 경로                    처리할 폴더 (기본: ~/storage/downloads/Moving)
#   --replace                     이미 커버가 있는 MP3 의 커버도 새로 넣음
#   --self-update                 이 스크립트를 저장소의 최신판으로 교체
#   --version                     버전 표시
#
# 필요한 것: ffmpeg (Termux: pkg install ffmpeg). 다른 스크립트·파이썬 모듈은 쓰지 않는다.
set -uo pipefail

VERSION="1.0.0"
DEFAULT_DIR="$HOME/storage/downloads/Moving"
AUDIO_EXTS="mp3 wav flac m4a aac ogg opus wma aiff aif mp4"
IMAGE_EXTS="jpg jpeg png webp bmp gif"
COVER_PX=240

usage() {
    cat <<'EOF'
asmr_mp3.sh — 오디오를 MP3 320 kbps CBR / 44,100 Hz / Stereo 로 통일하고 작품별 커버(240x240)를 넣는다

  bash asmr_mp3.sh              미리보기 (변환·삭제 없음)
  bash asmr_mp3.sh --apply      실제 적용
  bash asmr_mp3.sh --help       이 도움말
  옵션  --dir 경로    처리할 폴더 (기본: ~/storage/downloads/Moving, 하위 폴더 포함)
        --replace     이미 커버가 있는 MP3 도 새 커버로 바꿈
        --self-update 이 스크립트를 최신판으로 교체 (비공개 저장소: ~/.asmr_tools_token 에 GitHub 토큰)

작품 = 처리할 폴더 바로 아래 폴더 하나 (그 안의 하위 폴더 포함)
커버 = 그 작품 안의 이미지(jpg png webp bmp gif)
       1장이면 자동으로 쓰고, 여러 장이면 --apply 때 번호를 물어본다 (Enter = 이 작품은 커버 없이)
       다른 작품의 이미지는 쓰지 않는다. 원본 이미지는 건드리지 않는다.

오디오 (.mp3 .wav .flac .m4a .aac .ogg .opus .wma .aiff .aif .mp4)
  - MP3 가 아니거나 규격이 다른 MP3 : 커버와 함께 다시 인코딩 (메타데이터·챕터는 지움)
  - 규격에 맞는 MP3                 : 다시 인코딩하지 않음. 커버가 없으면 커버만 붙임 (오디오 그대로)
  - 같은 이름의 .mp3 가 이미 있으면 덮어쓰지 않음 (이름 충돌)
  - 이름에 .snow_v2_ / .snow_v3_ 가 들어간 파일은 제외

안전 순서
  임시 파일 생성 -> 검사(MP3, 320k, 44.1k, 2ch, 길이, 앞 3초·끝 3초 디코딩, 커버 240x240)
  -> 최종 이름으로 이동(덮어쓰기 없음) -> 같은 검사 한 번 더 -> 그다음에만 원본 삭제
  실패·Ctrl+C 때는 원본이 남는다. 파일 전체를 디코딩하지는 않으므로 중간 손상까지는 못 잡는다.
EOF
}

self_update() {
    local repo="${ASMR_TOOLS_REPO:-damedesuwa/asmr-mp3-tools}" branch="${ASMR_TOOLS_BRANCH:-main}"
    local me tok sha auth=()
    me="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tok="${GITHUB_TOKEN:-}"
    [ -z "$tok" ] && [ -f "$HOME/.asmr_tools_token" ] && tok="$(tr -d ' \r\n' <"$HOME/.asmr_tools_token")"
    [ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")
    # 브랜치 주소는 몇 분간 캐시되므로 최신 커밋 번호로 고정해서 받는다
    sha="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/commits/$branch" 2>/dev/null \
           | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -n 1 | grep -o '[0-9a-f]\{40\}')"
    if [ -z "$sha" ]; then
        echo "최신 버전 정보를 가져오지 못했습니다."
        [ -n "$tok" ] || echo "  비공개 저장소라면 ~/.asmr_tools_token 에 GitHub 토큰을 넣어 주세요."
        return 1
    fi
    curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github.raw" -o "$me.new" \
        "https://api.github.com/repos/$repo/contents/asmr_mp3.sh?ref=$sha" && bash -n "$me.new" || {
        rm -f "$me.new"; echo "받기 실패"; return 1; }
    chmod +x "$me.new" && mv -f "$me.new" "$me"
    echo "최신판으로 교체했습니다 (${sha:0:7}, v$(grep -m1 '^VERSION=' "$me" | cut -d'"' -f2)): $me"
}

MODE=dry DIR="$DEFAULT_DIR" REPLACE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) MODE=apply ;;
        --dry-run) MODE=dry ;;
        --replace) REPLACE=1 ;;
        --self-update) self_update; exit $? ;;
        --dir) shift; DIR="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        --version|-v) echo "asmr_mp3 $VERSION"; exit 0 ;;
        *) echo "알 수 없는 옵션: $1 (--help 참고)" >&2; exit 2 ;;
    esac
    shift
done
DIR="${DIR%/}"

for c in ffmpeg ffprobe find awk; do
    command -v "$c" >/dev/null 2>&1 || { echo "필요한 명령어가 없습니다: $c   (pkg install ffmpeg)" >&2; exit 1; }
done
grep -q libmp3lame <<<"$(ffmpeg -hide_banner -encoders 2>/dev/null)" || { echo "이 ffmpeg 에는 LAME 인코더가 없습니다." >&2; exit 1; }
[ -d "$DIR" ] || { echo "폴더가 없습니다: $DIR  (내부 저장소라면 termux-setup-storage 를 먼저)" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-$HOME}/.asmr_mp3.XXXXXX")"

# ------------------------------------------------------------------ 도구
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
fmt_time() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }
has_ext() { case " $2 " in *" $(lower "${1##*.}") "*) return 0 ;; esac; return 1; }

audio_info() {   # -> "codec|bit_rate|sample_rate|channels|duration"
    ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate,sample_rate,channels:format=duration \
        -of default=noprint_wrappers=1 "$1" 2>/dev/null |
    awk -F= '{v[$1]=$2} END {printf "%s|%s|%s|%s|%s", v["codec_name"], v["bit_rate"], v["sample_rate"], v["channels"], v["duration"]}'
}
cover_size() {   # 붙어 있는 커버의 "가로x세로", 없으면 빈 문자열
    ffprobe -v error -select_streams v -show_entries stream=width,height:stream_disposition=attached_pic \
        -of csv=p=0 "$1" 2>/dev/null | awk -F, '$3 == 1 { print $1 "x" $2; exit }'
}
image_size() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$1" 2>/dev/null; }
audio_md5() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -c copy -f md5 - 2>/dev/null; }
compliant() { local c b s ch d; IFS='|' read -r c b s ch d <<<"$1"; [ "$c" = mp3 ] && [ "$b" = 320000 ] && [ "$s" = 44100 ] && [ "$ch" = 2 ]; }
describe() { local c b s ch d; IFS='|' read -r c b s ch d <<<"$1"
    printf '%s %skbps %sHz %sch' "${c:-?}" "$( [[ "$b" =~ ^[0-9]+$ ]] && echo $((b / 1000)) || echo '?')" "${s:-?}" "${ch:-?}"; }

decodes() {   # decodes 파일 [앞쪽 옵션] : 3초가 오류 없이 디코딩되는가
    local f="$1"; shift
    local err; err="$(ffmpeg -nostdin -v error "$@" -i "$f" -t 3 -map 0:a:0 -f null - 2>&1)" && [ -z "$err" ]
}

verify() {   # verify 파일 기대커버(0/1) [기대오디오md5] -> 실패 이유 출력 후 1
    local f="$1" want_cover="$2" want_md5="${3:-}" c b s ch d
    [ -s "$f" ] || { echo "파일이 없거나 비어 있음"; return 1; }
    IFS='|' read -r c b s ch d <<<"$(audio_info "$f")"
    [ "$c" = mp3 ] || { echo "MP3 아님 ($c)"; return 1; }
    [ "$b" = 320000 ] || { echo "비트레이트 $b"; return 1; }
    [ "$s" = 44100 ] || { echo "샘플레이트 $s"; return 1; }
    [ "$ch" = 2 ] || { echo "채널 $ch"; return 1; }
    awk -v d="$d" 'BEGIN { exit !(d + 0 > 0) }' || { echo "재생 시간 0"; return 1; }
    decodes "$f" || { echo "앞부분 디코딩 실패"; return 1; }
    decodes "$f" -sseof -5 || { echo "끝부분 디코딩 실패"; return 1; }
    if [ "$want_cover" = 1 ] && [ "$(cover_size "$f")" != "${COVER_PX}x${COVER_PX}" ]; then
        echo "커버 ${COVER_PX}x${COVER_PX} 없음"; return 1
    fi
    if [ -n "$want_md5" ] && [ "$(audio_md5 "$f")" != "$want_md5" ]; then
        echo "오디오가 원본과 다름"; return 1
    fi
    return 0
}

# ------------------------------------------------------------------ 중단 처리
CUR_TMP="" CUR_BACKUP="" CUR_FINAL="" CUR_SRC=""
cleanup() { rm -rf -- "$WORK"; }
on_interrupt() {
    printf '\r\033[K\n중단 요청을 받았습니다. 정리 중…\n'
    [ -n "$CUR_TMP" ] && rm -f -- "$CUR_TMP"
    if [ -n "$CUR_BACKUP" ] && [ -f "$CUR_BACKUP" ] && [ ! -e "$CUR_FINAL" ]; then
        mv -n -- "$CUR_BACKUP" "$CUR_FINAL" && echo "원본을 원래 이름으로 되돌렸습니다: $CUR_FINAL"
    fi
    [ -n "$CUR_SRC" ] && echo "처리 중이던 원본은 그대로 있습니다: $CUR_SRC"
    stats
    cleanup
    exit 130
}
trap on_interrupt INT TERM
trap cleanup EXIT

# ------------------------------------------------------------------ 파일 수집
FILES=()
declare -A WORK_OF=() IMAGES=()
while IFS= read -r -d '' f; do
    base="${f##*/}"
    case "$base" in .*|*.snow_v2_*|*.snow_v3_*) continue ;; esac
    rel="${f#"$DIR"/}"
    w=""; [[ "$rel" == */* ]] && w="${rel%%/*}"
    if has_ext "$base" "$AUDIO_EXTS"; then
        FILES+=("$f"); WORK_OF["$f"]="$w"
    elif has_ext "$base" "$IMAGE_EXTS" && [ -n "$w" ]; then
        IMAGES["$w"]+="$f"$'\n'
    fi
done < <(find "$DIR" -type f -print0 | sort -z)
TOTAL=${#FILES[@]}

echo "asmr_mp3 v$VERSION — $([ $MODE = apply ] && echo '실제 적용' || echo '미리보기 (변경 없음)')"
echo "폴더: $DIR"
echo "출력: MP3 320 kbps CBR / 44,100 Hz / Stereo / LAME, 작품 커버 ${COVER_PX}x${COVER_PX}"
echo "오디오 파일: ${TOTAL}개"

# ------------------------------------------------------------------ 작품별 커버 고르기
declare -A COVER=() COVER_SRC=() NOTE=()
mapfile -t WORKS < <(for f in "${FILES[@]}"; do [ -n "${WORK_OF[$f]}" ] && printf '%s\n' "${WORK_OF[$f]}"; done | sort -u)
echo
echo "== 작품별 커버"
for w in "${WORKS[@]}"; do
    mapfile -t imgs < <(printf '%s' "${IMAGES[$w]:-}" | sed '/^$/d')
    pick=""
    if [ "${#imgs[@]}" -eq 0 ]; then
        NOTE[$w]="이미지 없음"
    elif [ "${#imgs[@]}" -eq 1 ]; then
        pick="${imgs[0]}"
    else
        echo "[$w] 이미지 ${#imgs[@]}장"
        for k in "${!imgs[@]}"; do
            printf '    %d) %s  (%s)\n' $((k + 1)) "${imgs[$k]#"$DIR/$w"/}" "$(image_size "${imgs[$k]}")"
        done
        if [ $MODE = apply ]; then
            printf '    커버로 쓸 번호 (Enter = 커버 없이): '
            read -r ans || ans=""
            if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#imgs[@]}" ]; then
                pick="${imgs[$((ans - 1))]}"
            else
                NOTE[$w]="이미지 여러 장, 고르지 않음"
            fi
        else
            NOTE[$w]="이미지 여러 장 — --apply 때 번호를 물어봄"
        fi
    fi
    if [ -n "$pick" ]; then
        out="$WORK/cover_$(printf '%s' "$w" | md5sum | cut -c1-12).jpg"
        if ffmpeg -nostdin -v error -y -i "$pick" -frames:v 1 \
               -vf "scale=${COVER_PX}:${COVER_PX}:force_original_aspect_ratio=increase:flags=lanczos,crop=${COVER_PX}:${COVER_PX},setsar=1" \
               -c:v mjpeg -pix_fmt yuvj420p -q:v 2 -update 1 "$out" && [ "$(image_size "$out")" = "${COVER_PX}x${COVER_PX}" ]; then
            COVER[$w]="$out"; COVER_SRC[$w]="${pick#"$DIR/$w"/}"
            echo "[$w] 커버: ${COVER_SRC[$w]} ($(image_size "$pick") → ${COVER_PX}x${COVER_PX})"
        else
            NOTE[$w]="이미지를 읽을 수 없음: ${pick#"$DIR/$w"/}"
        fi
    fi
    [ -n "${NOTE[$w]:-}" ] && echo "[$w] 커버 없음: ${NOTE[$w]}"
done

# ------------------------------------------------------------------ 처리
N_CONV=0 N_COVER=0 N_SKIP=0 N_CONFLICT=0 N_FAIL=0
FAILED=()
stats() {
    echo
    echo "============================================================"
    echo "결과 ($([ $MODE = apply ] && echo '실제 적용' || echo '미리보기'))"
    echo "  전체 대상 파일 : $TOTAL"
    echo "  변환 $([ $MODE = apply ] && echo '완료' || echo '예정')      : $N_CONV"
    echo "  커버만 추가    : $N_COVER"
    echo "  건너뜀         : $N_SKIP"
    echo "  이름 충돌      : $N_CONFLICT"
    echo "  실패           : $N_FAIL"
    for x in "${FAILED[@]}"; do echo "    - $x"; done
    echo "============================================================"
    [ $MODE = apply ] || echo "미리보기였습니다. 실제로 하려면 --apply 를 붙여 실행하세요."
}
fail() { echo "  실패: $2 (원본 보존)"; N_FAIL=$((N_FAIL + 1)); FAILED+=("$1 ($2)"); }

run_ffmpeg() {   # run_ffmpeg 길이 번호 ffmpeg인자... ; 진행률 표시
    local dur="$1" idx="$2"; shift 2
    local start=$SECONDS total_us rc errf="$WORK/err"
    total_us="$(awk -v d="$dur" 'BEGIN { printf "%d", d * 1000000 }')"
    ffmpeg -nostdin -hide_banner -v error -y "$@" -progress pipe:1 -nostats 2>"$errf" |
    while IFS='=' read -r k v; do
        [ "$k" = out_time_us ] && [[ "$v" =~ ^[0-9]+$ ]] || continue
        p=0; [ "$total_us" -gt 0 ] && p=$((v * 100 / total_us)); [ $p -gt 100 ] && p=100
        printf '\r\033[K  전체 작업 %3d%% | 파일 %d / %d | 현재 파일 %3d%% | 경과 시간 %s' \
            $(( ((idx - 1) * 100 + p) / TOTAL )) "$idx" "$TOTAL" "$p" "$(fmt_time $((SECONDS - start)))" >&2
    done
    rc=${PIPESTATUS[0]}
    printf '\r\033[K' >&2
    [ "$rc" -eq 0 ] || { FF_ERR="$(head -c 200 "$errf")"; return 1; }
    echo "  변환 완료 (경과 시간 $(fmt_time $((SECONDS - start))))"
}

place() {   # place 임시 최종 원본 기대커버 [기대md5] — 검증된 임시 파일을 최종 위치에 놓고 원본 정리
    local tmp="$1" final="$2" src="$3" want_cover="$4" want_md5="${5:-}" why size
    size=$(wc -c <"$tmp")
    if [ "$src" = "$final" ]; then               # 같은 이름 MP3 교체: 원본을 잠시 백업 이름으로
        local backup="$src.snow_v3_backup_$(date +%Y%m%d_%H%M%S)_$$"
        mv -n -- "$src" "$backup" && [ ! -e "$src" ] || { rm -f -- "$tmp"; echo "원본을 옮기지 못함"; return 1; }
        CUR_BACKUP="$backup"
        if mv -n -- "$tmp" "$final" && [ "$(wc -c <"$final")" = "$size" ] && why="$(verify "$final" "$want_cover" "$want_md5")"; then
            rm -f -- "$backup"; CUR_BACKUP=""; return 0
        fi
        [ -e "$tmp" ] || rm -f -- "$final"
        rm -f -- "$tmp"; mv -n -- "$backup" "$final"; CUR_BACKUP=""
        echo "최종 위치 재검증 실패, 원본 되돌림 ${why:+($why)}"; return 1
    fi
    [ -e "$final" ] && { rm -f -- "$tmp"; echo "CONFLICT"; return 1; }
    if mv -n -- "$tmp" "$final" && [ ! -e "$tmp" ] && [ "$(wc -c <"$final")" = "$size" ]; then
        CUR_TMP=""
        if why="$(verify "$final" "$want_cover" "$want_md5")"; then rm -f -- "$src"; return 0; fi
        rm -f -- "$final"; echo "최종 위치 재검증 실패 ($why)"; return 1
    fi
    rm -f -- "$tmp"; echo "최종 위치로 옮기지 못함"; return 1
}

echo
echo "== 파일"
declare -A CLAIMED=()
i=0
for src in "${FILES[@]}"; do
    i=$((i + 1))
    rel="${src#"$DIR"/}" base="${src##*/}" dir="${src%/*}" w="${WORK_OF[$src]}"
    cover=""; [ -n "$w" ] && cover="${COVER[$w]:-}"     # 작품 폴더 밖 파일은 커버 없음
    is_mp3=0; [ "$(lower "${base##*.}")" = mp3 ] && is_mp3=1
    final="$dir/${base%.*}.mp3"; [ $is_mp3 = 1 ] && final="$src"
    printf '[%d/%d] %s\n' "$i" "$TOTAL" "$rel"

    info="$(audio_info "$src")"
    sr="$(cut -d'|' -f3 <<<"$info")" dur="$(cut -d'|' -f5 <<<"$info")"
    [[ "$sr" =~ ^[1-9][0-9]*$ ]] || { fail "$rel" "오디오를 읽을 수 없음"; continue; }

    action=convert
    if [ $is_mp3 = 1 ] && compliant "$info"; then
        has="$(cover_size "$src")"
        if [ -z "$cover" ]; then
            echo "  건너뜀: 이미 규격${has:+, 커버 있음}"; N_SKIP=$((N_SKIP + 1)); continue
        elif [ -n "$has" ] && [ $REPLACE = 0 ]; then
            echo "  건너뜀: 이미 규격, 커버 있음 (바꾸려면 --replace)"; N_SKIP=$((N_SKIP + 1)); continue
        fi
        action=cover
        if [ -n "$has" ]; then echo "  커버 교체: ${COVER_SRC[$w]} (오디오는 그대로)"
        else echo "  커버만 추가: ${COVER_SRC[$w]} (오디오는 그대로)"; fi
    elif [ $is_mp3 = 1 ]; then
        echo "  재인코딩: $(describe "$info") → 320k 44.1k 2ch${cover:+ + 커버}"
    else
        key="$(lower "$final")"
        if [ -e "$final" ] || [ -n "${CLAIMED[$key]:-}" ]; then
            echo "  이름 충돌: ${final#"$DIR"/} 가 이미 있어 덮어쓰지 않음"; N_CONFLICT=$((N_CONFLICT + 1)); continue
        fi
        CLAIMED[$key]=1
        echo "  변환: $(describe "$info") → ${final#"$DIR"/}${cover:+ + 커버}"
    fi
    if [ $MODE != apply ]; then
        [ $action = cover ] && N_COVER=$((N_COVER + 1)) || N_CONV=$((N_CONV + 1))
        continue
    fi

    tmp="$dir/.snow_v3_tmp_$$_$i.mp3"
    CUR_TMP="$tmp" CUR_SRC="$src" CUR_FINAL="$final" FF_ERR=""
    want_cover=0; [ -n "$cover" ] && want_cover=1
    if [ $action = cover ]; then
        md5="$(audio_md5 "$src")"
        ffmpeg -nostdin -v error -y -i "$src" -i "$cover" -map 0:a:0 -map 1:0 -c copy \
            -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
            -disposition:v:0 attached_pic -f mp3 "$tmp" 2>"$WORK/err" || FF_ERR="$(head -c 200 "$WORK/err")"
    else
        md5=""
        args=(-i "$src")
        [ -n "$cover" ] && args+=(-i "$cover")
        args+=(-map 0:a:0 -map_metadata -1 -map_chapters -1 -c:a libmp3lame -b:a 320k -ar 44100 -ac 2 -write_id3v1 0)
        if [ -n "$cover" ]; then
            args+=(-map 1:0 -c:v copy -id3v2_version 3 -metadata:s:v title="Album cover"
                   -metadata:s:v comment="Cover (front)" -disposition:v:0 attached_pic)
        else
            args+=(-id3v2_version 0)
        fi
        run_ffmpeg "$dur" "$i" "${args[@]}" -f mp3 "$tmp" || true
    fi
    if [ -n "$FF_ERR" ] || [ ! -s "$tmp" ]; then
        rm -f -- "$tmp"; fail "$rel" "ffmpeg 오류: ${FF_ERR:-출력 없음}"; CUR_TMP="" CUR_SRC=""; continue
    fi
    if ! why="$(verify "$tmp" "$want_cover" "$md5")"; then
        rm -f -- "$tmp"; fail "$rel" "검증 실패: $why"; CUR_TMP="" CUR_SRC=""; continue
    fi
    if why="$(place "$tmp" "$final" "$src" "$want_cover" "$md5")"; then
        if [ $action = cover ]; then N_COVER=$((N_COVER + 1)); echo "  완료: 커버 적용, 오디오 동일 확인"
        else N_CONV=$((N_CONV + 1)); echo "  완료: ${final#"$DIR"/} 재검증 통과, 원본 삭제"; fi
    elif [ "$why" = CONFLICT ]; then
        echo "  이름 충돌: 처리 중에 ${final#"$DIR"/} 가 생겨 덮어쓰지 않음 (원본 보존)"; N_CONFLICT=$((N_CONFLICT + 1))
    else
        fail "$rel" "$why"
    fi
    CUR_TMP="" CUR_SRC="" CUR_BACKUP="" CUR_FINAL=""
done

stats
[ "$N_FAIL" -eq 0 ]
