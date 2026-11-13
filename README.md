# asmr-mp3-tools

Android **Termux**에서 쓰는 ASMR 음원 정리 도구 모음이다.
갤럭시 + Shanling M0 Pura 조합을 기준으로 만들었다.

| 파일 | 하는 일 |
|---|---|
| `snow_convert_final_v3.sh` | 폴더 안의 오디오를 MP3 320 kbps CBR / 44.1 kHz / Stereo로 통일한 뒤, 썸네일 단계까지 이어서 실행한다 |
| `asmr_cover_update.sh` | 작품별 썸네일 적용을 한 번에 한다 (스캔 → 요약 → `y` → 적용). `--self-update` 기능도 있다 |
| `asmr_cover_embed.sh` | 썸네일·이름 번역 본체. SD 카드(SAF)와 휴대폰 폴더(`--local-dir`)를 모두 지원한다 |
| `cover_pick.py` | 이미지가 여러 장인 작품에서 커버 후보를 미리보고 고른다 |
| `snowsky/` | SnowSky ECHO NANO용 도구. `snowsky_reorder.sh`는 SD 카드(SAF)의 MP3를 재생 순서대로 다시 복사하고, `snowsky_imgcheck.sh`는 폴더별 이미지 수를 읽기 전용으로 확인한다. `saf_*`는 SAF 동작 실험용 스크립트 (`damedesuwa/mymodel`에서 옮겨 옴) |

자세한 설명은 다음 문서에 있다.

- 변환: `docs/CONVERT.md`
- 썸네일, 커버 교체, 파일 이름 번역: `docs/COVER.md`

## 설치 (Termux)

```bash
pkg install python ffmpeg termux-api curl
pip install mutagen
termux-setup-storage
```

비공개 저장소라서 받으려면 GitHub 토큰이 필요하다.
GitHub → Settings → Developer settings → Fine-grained tokens에서 토큰을 만든다.

- 대상 저장소: `asmr-mp3-tools`만 지정한다.
- 권한: Contents를 Read-only로 준다.

```bash
echo '여기에_토큰' > ~/.asmr_tools_token && chmod 600 ~/.asmr_tools_token
curl -fsSL -H "Authorization: Bearer $(cat ~/.asmr_tools_token)" \
  -H "Accept: application/vnd.github.raw" -o ~/asmr_cover_update.sh \
  "https://api.github.com/repos/damedesuwa/asmr-mp3-tools/contents/asmr_cover_update.sh"
bash ~/asmr_cover_update.sh --self-update     # 나머지 파일을 모두 ~ 에 받음
```

이후 업데이트할 때는 `bash ~/asmr_cover_update.sh --self-update` 한 줄이면 된다.

## 자주 쓰는 명령

```bash
bash ~/snow_convert_final_v3.sh                 # Moving 폴더 변환 미리보기
bash ~/snow_convert_final_v3.sh --apply         # 변환 + 썸네일 적용

bash ~/asmr_cover_update.sh                                   # SD 카드 Asmr 폴더 썸네일
bash ~/asmr_cover_update.sh --local-dir ~/storage/downloads/Moving
bash ~/asmr_cover_update.sh --replace --work RJ01234567      # 한 작품의 커버 교체

bash ~/asmr_cover_embed.sh --export-names                     # 번역할 MP3 이름 목록 만들기
bash ~/asmr_cover_embed.sh --reuse-scan --rename-map 번역표.tsv          # 이름 번역 미리보기
bash ~/asmr_cover_embed.sh --reuse-scan --rename-map 번역표.tsv --apply  # 이름 번역 적용
```

## 공통 원칙

- 기본 실행은 항상 **미리보기**다. `--apply`를 붙여야 파일이 바뀐다.
- 원본은 결과물이 검증을 통과한 뒤에만 지우거나 교체한다. 실패하거나 중단하면 원본이 남는다.
- 다른 작품의 이미지는 절대 쓰지 않는다. 고를 수 없으면 적용하지 않고 후보만 보여 준다.
