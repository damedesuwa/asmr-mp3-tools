# asmr-mp3-tools

Android **Termux**에서 쓰는 ASMR 음원 정리 스크립트다. 파일은 **`asmr_mp3.sh` 하나**뿐이다.

## asmr_mp3.sh

휴대폰 폴더(기본 `~/storage/downloads/Moving`)를 한 번에 정리한다.

1. 오디오를 **MP3 320 kbps CBR / 44,100 Hz / Stereo**(LAME)로 통일한다.
2. 작품마다 이미지를 **240×240 Front Cover**로 잘라 넣는다.

```bash
bash ~/asmr_mp3.sh              # 미리보기 (아무것도 바꾸지 않음)
bash ~/asmr_mp3.sh --apply      # 실제 적용
bash ~/asmr_mp3.sh --apply --replace   # 이미 있는 커버도 새로 넣기
bash ~/asmr_mp3.sh --dir 다른폴더       # 다른 폴더
bash ~/asmr_mp3.sh --self-update        # 최신판으로 교체
bash ~/asmr_mp3.sh --help
```

### 작품과 커버

- **작품**: 처리할 폴더 바로 아래 폴더 하나다. 그 안의 하위 폴더도 같은 작품에 포함된다.
- **커버 원본**: 그 작품 안의 이미지(jpg png webp bmp gif)다.
  - 1장이면 자동으로 쓴다.
  - 여러 장이면 `--apply` 때 번호를 물어본다. 사진처럼 크기와 함께 목록이 나오고, Enter를 누르면 그 작품은 커버 없이 진행한다.
  - 다른 작품의 이미지는 절대 쓰지 않는다. 원본 이미지 파일은 건드리지 않는다.
- 작품 폴더 밖(처리할 폴더 바로 안)에 있는 오디오는 변환만 하고 커버는 넣지 않는다.

### 오디오

대상 확장자는 `.mp3 .wav .flac .m4a .aac .ogg .opus .wma .aiff .aif .mp4`다. `.mp4`는 첫 번째 오디오만 쓴다.

| 상황 | 처리 |
|---|---|
| MP3가 아님 | 같은 폴더에 `이름.mp3`로 변환하고 커버를 함께 넣는다. 메타데이터와 챕터는 지운다 |
| 규격이 다른 MP3 | 같은 방식으로 다시 인코딩한다 |
| 규격에 맞는 MP3 | 다시 인코딩하지 않는다. 커버가 없으면 **커버만** 붙이고, 오디오와 기존 태그는 그대로 둔다 |
| 같은 이름의 `.mp3`가 이미 있음 | 덮어쓰지 않는다 (이름 충돌) |
| 읽을 수 없는 파일 | 실패로 기록하고 원본을 그대로 둔다 |

이름에 `.snow_v2_` 또는 `.snow_v3_`가 들어간 파일과 `.`으로 시작하는 파일은 제외한다.

### 안전 순서

1. 같은 폴더에 숨김 임시 파일을 만든다.
2. 임시 파일을 검사한다.
   - MP3, 320k, 44.1k, 2채널, 길이 > 0인지 본다.
   - 앞 3초와 끝 부분 3초를 디코딩해 본다.
   - 커버를 넣었다면 240×240 커버가 있는지 본다.
   - 커버만 붙였다면 오디오가 원본과 같은지 본다.
3. 최종 이름으로 옮긴다. 이때 덮어쓰지 않는다.
4. 같은 검사를 한 번 더 한다.
5. 그다음에만 원본(같은 이름 MP3라면 잠시 옮겨 둔 백업)을 지운다.

실패하거나 Ctrl+C로 멈추면 원본이 남는다.
파일 전체를 디코딩하지는 않으므로 중간 부분의 손상까지 잡지는 못한다.

## 설치 (Termux, 처음 한 번)

```bash
pkg install ffmpeg curl
termux-setup-storage          # 휴대폰 저장소(~/storage/downloads) 권한
```

비공개 저장소라서 받으려면 GitHub 토큰이 필요하다.
GitHub → Settings → Developer settings → **Fine-grained tokens**에서 토큰을 만든다.

- 대상 저장소: `asmr-mp3-tools`만 지정한다.
- 권한: Contents를 Read-only로 준다.

```bash
echo '여기에_토큰' > ~/.asmr_tools_token && chmod 600 ~/.asmr_tools_token
curl -fsSL -H "Authorization: Bearer $(cat ~/.asmr_tools_token)" \
  -H "Accept: application/vnd.github.raw" -o ~/asmr_mp3.sh \
  "https://api.github.com/repos/damedesuwa/asmr-mp3-tools/contents/asmr_mp3.sh"
bash ~/asmr_mp3.sh --help
```

이후 업데이트할 때는 `bash ~/asmr_mp3.sh --self-update` 한 줄이면 된다.

## 개발

```bash
bash tests/run.sh      # 필요: bash, python3 + mutagen, ffmpeg(libmp3lame)
```

- **시험 환경:** 임시 폴더에 시험용 오디오·이미지를 만들어 돌린다. 네트워크는 쓰지 않는다.
- **작업 폴더 유지:** `KEEP=1 bash tests/run.sh`로 실행하면 작업 폴더를 지우지 않는다.
- **CI:** GitHub에 올릴 때마다 같은 시험이 자동으로 돈다(`.github/workflows/test.yml`).
- **수정한 뒤에는:** `bash tests/run.sh`를 통과시키고 `CHANGELOG.md`에 한 줄을 적는다.
