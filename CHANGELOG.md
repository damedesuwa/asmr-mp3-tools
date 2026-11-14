# 변경 기록

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
