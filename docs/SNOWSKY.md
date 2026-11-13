# SnowSky ECHO NANO 도구 — snowsky/

FiiO SnowSky ECHO NANO는 파일을 SD 카드 디렉터리 엔트리 순서(복사 순서)로 보여 준다.
이 폴더의 도구는 그 순서를 맞추고 점검한다. 모두 Termux + SAF용이다.

| 파일 | 하는 일 |
|---|---|
| `snowsky_reorder.sh` | `Asmr/<작품>/`과 하위 폴더 전부를 트랙 번호 순서대로 다시 생성한다. 바이트 그대로 복사만 하고(재인코딩·태그 수정·이름 변경 없음), 모든 파일을 백업·해시 검증한 뒤 진행한다. 실패하면 즉시 멈추고 백업을 지우지 않는다 (`--restore`). |
| `snowsky_imgcheck.sh` | 작품 폴더마다 이미지 파일이 정확히 1개인지 읽기 전용으로 검사한다. `--deep`이면 하위 폴더까지 검사한다. |
| `snowsky_audit.sh` | `snowsky_reorder.sh` 실행 로그를 읽어, 성공 처리된 작품마다 계획한 파일·폴더 수와 실제 수가 같은지 확인한다. SD 카드에는 접근하지 않는다. |
| `experiments/saf_*.sh` | SAF 동작을 조사하던 실험 스크립트다 (`saf_probe*`는 읽기 전용, `saf_experiment*`는 `Asmr/__saf_test__` 안에서만 쓴다). 평소에는 쓸 일이 없다. |

자세한 옵션은 각 스크립트 맨 위의 설명을 본다. `--self-update`로 `snowsky_*.sh` 세 파일도 함께 받아진다.
