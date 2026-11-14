# asmr-mp3-tools

Android **Termux**에서 쓰는 ASMR 음원 정리 도구 모음이다.
Galaxy 휴대폰 + 외장 SD 카드 + Shanling M0 Pura / FiiO SnowSky 조합을 기준으로 만들었다.

| 하고 싶은 일 | 명령 | 문서 |
|---|---|---|
| 휴대폰 폴더의 오디오를 MP3 320k로 통일하고 썸네일까지 | `bash ~/snow_convert_final_v3.sh --apply` | [docs/CONVERT.md](docs/CONVERT.md) |
| SD 카드 작품들에 썸네일 넣기 | `bash ~/asmr_cover_update.sh` | [docs/COVER.md](docs/COVER.md) |
| 한 작품의 커버 바꾸기 | `bash ~/asmr_cover_update.sh --replace --work RJ01234567` | [docs/COVER.md](docs/COVER.md) |
| SnowSky 재생 순서 맞추기 | `bash ~/snowsky_reorder.sh` | [docs/SNOWSKY.md](docs/SNOWSKY.md) |
| 도구를 최신판으로 | `bash ~/asmr_cover_update.sh --self-update` | 아래 |

## 공통 원칙

- 기본 실행은 항상 **미리보기**다. `--apply`(또는 확인 질문에 `y`)가 있어야 파일이 바뀐다.
- 원본은 결과물이 검증을 통과한 뒤에만 지우거나 교체한다. 실패하거나 중단하면 원본이 남는다.
- **작품** = 검색 위치 바로 아래 폴더 하나(그 안의 하위 폴더 포함). 다른 작품의 이미지는 절대 쓰지 않고, 고를 수 없으면 적용하지 않고 후보만 보여 준다.

## 설치 (Termux, 처음 한 번)

```bash
pkg install python ffmpeg termux-api curl
pip install mutagen
termux-setup-storage          # 휴대폰 저장소(~/storage/downloads) 권한
termux-saf-managedir          # SD 카드를 쓸 때: SD 카드 → Asmr 폴더 선택
```

Termux:API 앱은 Termux와 같은 출처(F-Droid 또는 GitHub)에서 설치해야 한다.

비공개 저장소라서 받으려면 GitHub 토큰이 필요하다.
GitHub → Settings → Developer settings → **Fine-grained tokens**에서 토큰을 만든다.

- 대상 저장소: `asmr-mp3-tools`만 지정한다.
- 권한: Contents를 Read-only로 준다.

```bash
echo '여기에_토큰' > ~/.asmr_tools_token && chmod 600 ~/.asmr_tools_token
curl -fsSL -H "Authorization: Bearer $(cat ~/.asmr_tools_token)" \
  -H "Accept: application/vnd.github.raw" -o ~/asmr_cover_update.sh \
  "https://api.github.com/repos/damedesuwa/asmr-mp3-tools/contents/asmr_cover_update.sh"
bash ~/asmr_cover_update.sh --self-update
```

`--self-update`는 아래 파일을 모두 `asmr_cover_update.sh`가 있는 폴더(위 예에서는 `~`)에 받는다.

- `snow_convert_final_v3.sh`
- `asmr_cover_update.sh`
- `asmr_cover_embed.sh`
- `cover_pick.py`
- `snowsky_*.sh`

파일은 모두 받아진 뒤에만 한꺼번에 교체된다.

## 저장소 구성

```
snow_convert_final_v3.sh   변환 (+ 끝나면 썸네일 단계)
asmr_cover_update.sh       썸네일 한 번에 적용, --self-update
asmr_cover_embed.sh        썸네일·커버 교체 본체 (SAF / --local-dir)
cover_pick.py              이미지가 여러 장인 작품의 커버 고르기
snowsky/                   SnowSky ECHO NANO 재생 순서 도구 (experiments/ 는 SAF 실험)
docs/                      도구별 설명
tests/run.sh               휴대폰 없이 전체 시험 (tests/mock = 가짜 termux-saf-*)
```

휴대폰에서 실행하는 파일이 저장소 맨 위에 있는 것은 `--self-update`가 받는 경로와 맞추기 위해서다.
옮기려면 `asmr_cover_update.sh`의 `TOOL_FILES`도 같이 고쳐야 한다.

## 개발

```bash
bash tests/run.sh      # 필요: bash, python3 + mutagen, ffmpeg(libmp3lame)
```

시험은 임시 폴더 하나를 SD 카드의 `Asmr` 폴더처럼 보여 주는 가짜 `termux-saf-*`(`tests/mock/`)로 돈다.
진짜 SD 카드나 네트워크는 쓰지 않는다. 변환, Ctrl+C 중단, 썸네일 규칙, 덮어쓰기가 잘리지 않는 기기에서의 중단, 커버 교체, 휴대폰 폴더 모드를 확인한다.
`KEEP=1 bash tests/run.sh`로 실행하면 작업 폴더를 지우지 않는다.

수정한 뒤에는 `bash tests/run.sh`를 통과시키고 `CHANGELOG.md`에 한 줄을 적는다.
