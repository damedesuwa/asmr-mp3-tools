#!/usr/bin/env bash
# snow_convert_final_v3.sh — 폴더 안의 오디오를 MP3 320 kbps CBR / 44.1 kHz / Stereo 로 통일
#
#   bash snow_convert_final_v3.sh              미리보기 (아무것도 바꾸지 않음)
#   bash snow_convert_final_v3.sh --dry-run    미리보기
#   bash snow_convert_final_v3.sh --apply      실제 변환
#   bash snow_convert_final_v3.sh --help       도움말
#   --dir 경로                                  검색 위치 변경 (기본: ~/storage/downloads/Moving)
#   --no-cover                                  변환 뒤 썸네일 단계를 건너뜀
#
# 변환이 끝나면 같은 폴더에 썸네일 단계(asmr_cover_update.sh)를 이어서 실행한다:
#   작품 폴더(검색 위치 바로 아래 폴더) 안의 이미지가 1장이면 그 작품의 커버 없는 MP3 전부에
#   240x240 Front Cover 를 넣는다. 미리보기에서는 썸네일도 미리보기만 한다.
#
# 안전 순서: 임시 MP3 생성 -> 규격 검사 -> 앞 3초/끝 3초 디코딩 -> 최종 이름으로 이동
#            -> 최종 파일 재검증 -> 원본(또는 재인코딩용 백업) 삭제. 실패하면 원본은 그대로 남는다.
set -uo pipefail

VERSION="v3"
DEFAULT_DIR="$HOME/storage/downloads/Moving"
TARGET_BR=320000
TARGET_SR=44100
TARGET_CH=2
EXTS="mp3 wav flac m4a aac ogg opus wma aiff aif mp4"

usage() {
    cat <<'EOF'
snow_convert_final_v3.sh — 오디오를 MP3 320 kbps CBR / 44,100 Hz / Stereo 로 통일

사용법
  bash snow_convert_final_v3.sh              미리보기 (변환·삭제 없음)
  bash snow_convert_final_v3.sh --dry-run    미리보기
  bash snow_convert_final_v3.sh --apply      실제 변환
  bash snow_convert_final_v3.sh --help       이 도움말
  옵션: --dir 경로   검색할 폴더 (기본: ~/storage/downloads/Moving, 하위 폴더 포함)
        --no-cover   변환 뒤 썸네일 단계를 건너뜀

썸네일 (변환 뒤 자동)
  검색 위치 바로 아래 폴더 하나를 작품 하나로 보고, 작품 안 이미지(JPG/PNG/WEBP…)가
  1장이면 그 작품의 커버 없는 MP3 전부에 240x240 Front Cover 로 넣는다.
  이미지가 없거나 여러 장인 작품은 넣지 않고 알려 준다. (asmr_cover_update.sh 필요)

대상: .mp3 .wav .flac .m4a .aac .ogg .opus .wma .aiff .aif .mp4(첫 오디오 스트림만)
제외: 이름에 .snow_v2_ / .snow_v3_ 가 들어간 임시·백업 파일

처리
  - MP3 가 아닌 파일 : 같은 폴더에 '이름.mp3' 로 변환, 최종 위치에서 재검증 통과 후 원본 삭제
                       '이름.mp3' 가 이미 있으면 덮어쓰지 않고 '이름 충돌'로 건너뜀
  - 규격에 맞는 MP3  : 그대로 둠
  - 규격이 다른 MP3  : 재인코딩. 교체하는 동안만 원본을 '이름.mp3.snow_v3_backup_날짜_시간_PID' 로
                       옮겨 두고, 새 파일이 최종 위치에서 재검증을 통과하면 그 백업을 삭제
  - 출력은 메타데이터·챕터·커버 없이 오디오만 담는다

검증 (최종 위치로 옮기기 전)
  파일 존재, 0바이트 아님, MP3 코덱, 320 kbps, 44,100 Hz, 2채널, 재생 시간 > 0,
  앞 3초 디코딩, 끝 5초 지점부터 3초 디코딩
  ※ 파일 전체를 디코딩하지는 않으므로 중간 부분 손상까지 완벽히 잡지는 못한다.
EOF
}

MODE="dry"
DIR="$DEFAULT_DIR"
COVER=1
while [ $# -gt 0 ]; do
    case "$1" in
        --apply)   MODE="apply" ;;
        --dry-run) MODE="dry" ;;
        --help|-h) usage; exit 0 ;;
        --dir)     shift; DIR="${1:-}" ;;
        --no-cover) COVER=0 ;;
        *) echo "알 수 없는 옵션: $1 (--help 참고)" >&2; exit 2 ;;
    esac
    shift
done

for c in ffmpeg ffprobe find; do
    command -v "$c" >/dev/null 2>&1 || { echo "필요한 명령어가 없습니다: $c   (pkg install ffmpeg)" >&2; exit 1; }
done
if ! grep -q libmp3lame <<<"$(ffmpeg -hide_banner -encoders 2>/dev/null)"; then
    echo "이 ffmpeg 에는 LAME(libmp3lame) 인코더가 없습니다." >&2
    exit 1
fi
if [ ! -d "$DIR" ]; then
    echo "폴더가 없습니다: $DIR" >&2
    echo "  내부 저장소라면 먼저 termux-setup-storage 를 실행했는지 확인하세요." >&2
    exit 1
fi

# ---------------------------------------------------------------- 공통 도구
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

probe() {   # probe 파일 -> "codec|bit_rate|sample_rate|channels|duration" (첫 오디오 스트림)
    ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate,sample_rate,channels:format=duration \
        -of default=noprint_wrappers=1 "$1" 2>/dev/null |
    awk -F= '{v[$1]=$2} END {printf "%s|%s|%s|%s|%s", v["codec_name"], v["bit_rate"], v["sample_rate"], v["channels"], v["duration"]}'
}

is_compliant() {   # 이미 규격인 MP3 인가
    local codec br sr ch dur
    IFS='|' read -r codec br sr ch dur <<<"$(probe "$1")"
    [ "$codec" = "mp3" ] && [ "$br" = "$TARGET_BR" ] && [ "$sr" = "$TARGET_SR" ] && [ "$ch" = "$TARGET_CH" ]
}

describe() {   # 사람이 읽을 규격 요약
    local codec br sr ch dur
    IFS='|' read -r codec br sr ch dur <<<"$(probe "$1")"
    local kb="?"
    [[ "$br" =~ ^[0-9]+$ ]] && kb=$((br / 1000))
    printf '%s %skbps %sHz %sch' "${codec:-?}" "$kb" "${sr:-?}" "${ch:-?}"
}

fmt_time() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }

decode_ok() {   # decode_ok 파일 [ffmpeg 앞쪽 옵션...] : 오류 없이 디코딩되는가
    local f="$1"; shift
    local err
    err="$(ffmpeg -nostdin -hide_banner -v error "$@" -i "$f" -t 3 -map 0:a:0 -f null - 2>&1)" || return 1
    [ -z "$err" ]
}

verify() {   # verify 임시파일 -> 실패 시 이유를 출력하고 1
    local f="$1" codec br sr ch dur
    [ -f "$f" ] || { echo "파일이 생성되지 않음"; return 1; }
    [ -s "$f" ] || { echo "빈 파일"; return 1; }
    IFS='|' read -r codec br sr ch dur <<<"$(probe "$f")"
    [ "$codec" = "mp3" ] || { echo "코덱이 MP3 아님 ($codec)"; return 1; }
    [ "$br" = "$TARGET_BR" ] || { echo "비트레이트 $br (320000 아님)"; return 1; }
    [ "$sr" = "$TARGET_SR" ] || { echo "샘플레이트 $sr (44100 아님)"; return 1; }
    [ "$ch" = "$TARGET_CH" ] || { echo "채널 $ch (2 아님)"; return 1; }
    awk -v d="$dur" 'BEGIN { exit !(d + 0 > 0) }' || { echo "재생 시간 0"; return 1; }
    decode_ok "$f" || { echo "앞부분 3초 디코딩 실패"; return 1; }
    decode_ok "$f" -sseof -5 || { echo "끝부분 디코딩 실패"; return 1; }
    return 0
}

# ---------------------------------------------------------------- 중단 처리
CUR_TMP=""       # 지금 만들고 있는 임시 MP3
CUR_SRC=""       # 지금 처리 중인 원본
CUR_BACKUP=""    # MP3 재인코딩 중 원본을 옮겨 둔 백업 (최종 배치 전이면 되돌린다)
CUR_FINAL=""
on_interrupt() {
    printf '\n중단 요청을 받았습니다. 정리 중…\n'
    [ -n "$CUR_TMP" ] && rm -f -- "$CUR_TMP"
    if [ -n "$CUR_BACKUP" ] && [ -f "$CUR_BACKUP" ] && [ ! -e "$CUR_FINAL" ]; then
        mv -n -- "$CUR_BACKUP" "$CUR_FINAL" && echo "원본을 원래 이름으로 되돌렸습니다: $CUR_FINAL"
    fi
    [ -n "$CUR_SRC" ] && echo "처리 중이던 원본은 그대로 있습니다: $CUR_SRC"
    print_stats
    exit 130
}
trap on_interrupt INT TERM

# ---------------------------------------------------------------- 대상 수집
FILES=()
while IFS= read -r -d '' f; do
    base="${f##*/}"
    case "$base" in
        *.snow_v2_*|*.snow_v3_*|.snow_v2_*|.snow_v3_*) continue ;;
    esac
    ext="$(lower "${base##*.}")"
    [ "$base" = "$ext" ] && continue
    case " $EXTS " in *" $ext "*) FILES+=("$f") ;; esac
done < <(find "$DIR" -type f -print0 | sort -z)

TOTAL=${#FILES[@]}
N_DONE=0; N_SKIP=0; N_CONFLICT=0; N_FAIL=0
FAILED=()

print_stats() {
    echo
    echo "============================================================"
    echo "결과 ($([ "$MODE" = apply ] && echo '실제 변환' || echo '미리보기'))"
    echo "  전체 대상 파일 : $TOTAL"
    echo "  변환 $([ "$MODE" = apply ] && echo '완료' || echo '예정') 파일 : $N_DONE"
    echo "  건너뛴 파일    : $N_SKIP"
    echo "  이름 충돌 파일 : $N_CONFLICT"
    echo "  실패 파일      : $N_FAIL"
    for x in "${FAILED[@]}"; do echo "    - $x"; done
    echo "============================================================"
    [ "$MODE" = apply ] || echo "미리보기였습니다. 실제로 변환하려면 --apply 를 붙여 실행하세요."
}

echo "snow_convert_final $VERSION — $([ "$MODE" = apply ] && echo '실제 변환' || echo '미리보기 (변경 없음)')"
echo "검색 위치: $DIR (하위 폴더 포함)"
echo "출력 규격: MP3 320 kbps CBR / 44,100 Hz / Stereo / LAME / 메타데이터 없음"
echo "대상 파일: $TOTAL개"
echo

declare -A CLAIMED=()   # 미리보기에서 같은 출력 이름을 두 원본이 노리는 경우

# ---------------------------------------------------------------- 변환 1건
CONVERT_ERR=""
convert() {   # convert 원본 임시출력 길이(초) 번호 ; 진행률은 화면(stderr)에, 실패 이유는 CONVERT_ERR
    local src="$1" tmp="$2" dur="$3" idx="$4"
    local start=$SECONDS errf total_us rc
    errf="$(mktemp "${TMPDIR:-$HOME}/.snow_v3_err.XXXXXX")"
    total_us="$(awk -v d="$dur" 'BEGIN { printf "%d", d * 1000000 }')"
    ffmpeg -nostdin -hide_banner -v error -y -i "$src" \
        -map 0:a:0 -vn -sn -dn \
        -map_metadata -1 -map_chapters -1 \
        -c:a libmp3lame -b:a 320k -ar "$TARGET_SR" -ac "$TARGET_CH" \
        -id3v2_version 0 -write_id3v1 0 \
        -progress pipe:1 -nostats -f mp3 "$tmp" 2>"$errf" |
    while IFS='=' read -r key val; do
        [ "$key" = "out_time_us" ] || continue
        [[ "$val" =~ ^[0-9]+$ ]] || continue
        pct=0
        [ "$total_us" -gt 0 ] && pct=$((val * 100 / total_us))
        [ "$pct" -gt 100 ] && pct=100
        all=$(( ((idx - 1) * 100 + pct) / TOTAL ))
        printf '\r\033[K  전체 작업 %3d%% | 파일 %d / %d | 현재 파일 %3d%% | 경과 시간 %s' \
            "$all" "$idx" "$TOTAL" "$pct" "$(fmt_time $((SECONDS - start)))" >&2
    done
    rc=${PIPESTATUS[0]}
    printf '\r\033[K' >&2
    CONVERT_ERR="$(head -c 300 "$errf")"
    rm -f -- "$errf"
    if [ "$rc" -ne 0 ]; then
        [ -n "$CONVERT_ERR" ] || CONVERT_ERR="ffmpeg 종료 코드 $rc"
        return 1
    fi
    echo "  변환 완료 (경과 시간 $(fmt_time $((SECONDS - start))))"
    return 0
}

# ---------------------------------------------------------------- 본 처리
i=0
for src in "${FILES[@]}"; do
    i=$((i + 1))
    rel="${src#"$DIR"/}"
    base="${src##*/}"
    dir="${src%/*}"
    stem="${base%.*}"
    ext="$(lower "${base##*.}")"
    final="$dir/$stem.mp3"
    is_mp3=0
    [ "$ext" = "mp3" ] && { is_mp3=1; final="$src"; }

    printf '[%d/%d] %s\n' "$i" "$TOTAL" "$rel"

    info="$(probe "$src")"
    if [ -z "${info%%|*}" ]; then
        echo "  실패: 오디오 스트림을 찾을 수 없음"
        N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (오디오 없음)")
        continue
    fi
    dur="$(printf '%s' "$info" | awk -F'|' '{print $5}')"
    sr0="$(printf '%s' "$info" | awk -F'|' '{print $3}')"
    if ! [[ "$sr0" =~ ^[1-9][0-9]*$ ]]; then
        echo "  실패: 오디오를 읽을 수 없음 (손상되었거나 지원하지 않는 형식)"
        N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (오디오를 읽을 수 없음)")
        continue
    fi

    if [ "$is_mp3" -eq 1 ]; then
        if is_compliant "$src"; then
            echo "  건너뜀: 이미 320 kbps / 44.1 kHz / Stereo"
            N_SKIP=$((N_SKIP + 1))
            continue
        fi
        echo "  재인코딩: $(describe "$src") → mp3 320kbps 44100Hz 2ch (검증 후 원본 삭제)"
    else
        key="$(lower "$final")"
        if [ -e "$final" ] || [ -n "${CLAIMED[$key]:-}" ]; then
            echo "  이름 충돌: ${final#"$DIR"/} 가 이미 있어 덮어쓰지 않음"
            N_CONFLICT=$((N_CONFLICT + 1))
            continue
        fi
        CLAIMED[$key]=1
        echo "  변환: $(describe "$src") → ${final#"$DIR"/} (성공 시 원본 삭제)"
    fi

    if [ "$MODE" != "apply" ]; then
        N_DONE=$((N_DONE + 1))
        continue
    fi

    # ---- 실제 변환
    tmp="$dir/.snow_v3_tmp_$$_${i}.mp3"
    CUR_TMP="$tmp"; CUR_SRC="$src"; CUR_BACKUP=""; CUR_FINAL="$final"
    if ! convert "$src" "$tmp" "$dur" "$i"; then
        why="변환 실패: $CONVERT_ERR"
    elif ! why="$(verify "$tmp")"; then
        why="검증 실패: $why"
    else
        why=""
    fi
    if [ -n "$why" ]; then
        echo "  실패: $why (원본 보존)"
        rm -f -- "$tmp"
        N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel ($why)")
        CUR_TMP=""; CUR_SRC=""
        continue
    fi
    echo "  검증 통과: $(describe "$tmp"), 앞 3초·끝 3초 디코딩 정상"
    tmp_size=$(wc -c <"$tmp")

    if [ "$is_mp3" -eq 1 ]; then
        backup="$src.snow_v3_backup_$(date +%Y%m%d_%H%M%S)_$$"
        if ! mv -n -- "$src" "$backup" || [ -e "$src" ]; then
            echo "  실패: 원본을 백업 이름으로 옮기지 못함 (원본 보존)"
            rm -f -- "$tmp"
            N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (백업 실패)")
            CUR_TMP=""; CUR_SRC=""
            continue
        fi
        CUR_BACKUP="$backup"
        if mv -n -- "$tmp" "$final" && [ ! -e "$tmp" ] && [ "$(wc -c <"$final")" = "$tmp_size" ] \
           && why="$(verify "$final")"; then
            CUR_TMP=""
            rm -f -- "$backup"
            echo "  완료: 교체 후 최종 파일 재검증 통과, 원본(백업) 삭제"
            N_DONE=$((N_DONE + 1))
        else
            # 새 파일이 자리를 잡지 못했거나 재검증에 실패: 원본을 원래 이름으로 되돌린다
            if [ -e "$final" ] && [ ! -e "$tmp" ]; then rm -f -- "$final"; fi
            mv -n -- "$backup" "$final"
            rm -f -- "$tmp"
            echo "  실패: 최종 배치/재검증 실패로 원본을 되돌림 ${why:+($why)}"
            N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (최종 배치 실패)")
        fi
    else
        if [ -e "$final" ]; then
            echo "  이름 충돌: 변환 중에 ${final#"$DIR"/} 가 생겨 덮어쓰지 않음 (원본 보존)"
            rm -f -- "$tmp"
            N_CONFLICT=$((N_CONFLICT + 1))
        elif mv -n -- "$tmp" "$final" && [ ! -e "$tmp" ] && [ "$(wc -c <"$final")" = "$tmp_size" ]; then
            CUR_TMP=""
            if why="$(verify "$final")"; then
                rm -f -- "$src"
                echo "  완료: ${final#"$DIR"/} 재검증 통과, 원본 삭제"
                N_DONE=$((N_DONE + 1))
            else
                rm -f -- "$final"
                echo "  실패: 최종 파일 재검증 실패 ($why) — 원본 보존"
                N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (최종 재검증 실패)")
            fi
        else
            rm -f -- "$tmp"
            echo "  실패: 최종 위치로 옮기지 못함 (원본 보존)"
            N_FAIL=$((N_FAIL + 1)); FAILED+=("$rel (이동 실패)")
        fi
    fi
    CUR_TMP=""; CUR_SRC=""; CUR_BACKUP=""; CUR_FINAL=""
done

print_stats

# ---------------------------------------------------------------- 썸네일 단계
cover_step() {
    [ "$COVER" -eq 1 ] || return 0
    local here w=""
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for c in "$here/asmr_cover_update.sh" "$HOME/bin/asmr_cover_update.sh"; do
        [ -f "$c" ] && { w="$c"; break; }
    done
    echo
    echo "############################################################"
    echo "썸네일 단계"
    if [ -z "$w" ]; then
        echo "  asmr_cover_update.sh 를 찾지 못해 건너뜁니다 (이 스크립트와 같은 폴더에 두세요. --self-update 로 함께 받아집니다)."
        return 0
    fi
    trap - INT TERM
    if [ "$MODE" = "apply" ]; then
        printf 'y\n' | bash "$w" --local-dir "$DIR"
    else
        echo "  (미리보기: 아직 MP3 가 아닌 파일은 변환 뒤에 대상이 됩니다)"
        printf 'n\n' | bash "$w" --local-dir "$DIR"
    fi
}
cover_step
[ "$N_FAIL" -eq 0 ]
