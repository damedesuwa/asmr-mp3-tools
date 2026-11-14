# 변경 기록

## 2026-11-14 — asmr_mp3.sh 하나만 남김

- **삭제:** SD 카드(SAF) 커버 도구(`asmr_cover_update.sh`, `asmr_cover_embed.sh`), SnowSky 도구(`snowsky/`), 관련 문서(`docs/`)와 시험(`tests/mock/`)을 지웠다.
- **남은 것:** 저장소에는 `asmr_mp3.sh`와 그 시험만 남았다.

## 2026-11-14 — 변환과 커버를 asmr_mp3.sh 하나로

- **`asmr_mp3.sh` 추가:** 변환(MP3 320k/44.1k/Stereo)과 작품별 커버(240×240)를 한 파일, 한 번의 실행으로 처리한다. ffmpeg 말고는 다른 스크립트나 파이썬 모듈이 필요 없다.
  - 이미지가 여러 장인 작품은 `--apply` 때 번호를 물어본다.
  - 규격에 맞는 MP3는 다시 인코딩하지 않고 커버만 붙인다. 오디오는 그대로라는 것을 검사로 확인한다.
  - `--replace`로 이미 있는 커버도 바꿀 수 있고, `--self-update`로 자기 자신을 최신판으로 교체한다.
- **합쳐서 없앤 것:** `snow_convert_final_v3.sh`, `cover_pick.py`, `docs/CONVERT.md`를 지웠다.
- **SD 카드용 도구:** `asmr_cover_update.sh`와 `asmr_cover_embed.sh`는 SD 카드(SAF)용으로 남겼다. `--self-update`가 받는 목록을 새 구성에 맞췄다.

## 2026-11-14 — 쓰지 않는 기능 제거

- **MP3 파일 이름 번역 제거:** `--export-names`, `--rename-map` 옵션과 `docs/RENAME.md`를 없앴다. 관련 시험 항목도 함께 뺐다.

## 2026-11-13 — 저장소 정리

- **폴더 정리:** 휴대폰에서 실행하는 도구는 맨 위에 둔다. SnowSky 도구는 `snowsky/`, SAF 실험 스크립트는 `snowsky/experiments/`로 모았다.
- **문서 재정리:** 문서를 도구별로 나눴다. 변환은 `docs/CONVERT.md`, 썸네일은 `docs/COVER.md`, SnowSky는 `docs/SNOWSKY.md`다. `mymodel` 시절의 `~/bin` 경로 안내는 모두 `~/`로 고쳤다.
- **`--self-update`:** `snowsky_*.sh`도 함께 받는다. 파일을 모두 받은 뒤에만 한꺼번에 교체하고, 받은 위치를 알려 준다. 시험용으로 저장소·브랜치·파일 목록을 바꾸는 환경 변수 `ASMR_TOOLS_REPO`, `ASMR_TOOLS_BRANCH`, `ASMR_TOOLS_FILES`를 추가했다.
- **`tests/run.sh` 추가:** 가짜 `termux-saf-*`로 휴대폰 없이 40개 항목을 시험한다.
- **안내 문구:** `cover_pick.py`가 자기 실제 경로로 다음 명령을 안내한다.

## 2026-11-13 — 처음 옮겨 옴

- `damedesuwa/mymodel`에서 옮겨 왔다.
  - `snow_convert_final_v3.sh`: 변환한 뒤 썸네일 단계까지 이어서 실행한다.
  - `asmr_cover_update.sh`
  - `asmr_cover_embed.sh`
  - `cover_pick.py`
  - SnowSky 도구
