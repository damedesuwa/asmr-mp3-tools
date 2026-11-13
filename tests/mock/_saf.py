"""termux-saf-* 의 가짜 구현. MOCK_SAF_BASE 폴더를 SD 카드의 Asmr 폴더처럼 보여 준다.
MOCK_SAF_NO_TRUNC=1 이면 덮어쓰기가 truncate 하지 않는 기기를 흉내 낸다."""
import json
import os
import shutil
import sys
import urllib.parse

BASE = os.environ["MOCK_SAF_BASE"]
ROOT = "content://mock/tree/0000-0000%3AAsmr"


def path(uri):
    if uri == ROOT:
        return BASE
    return os.path.join(BASE, urllib.parse.unquote(uri[len(ROOT + "/document/"):]))


def uri(p):
    if os.path.abspath(p) == os.path.abspath(BASE):
        return ROOT
    return ROOT + "/document/" + urllib.parse.quote(os.path.relpath(p, BASE), safe="")


def entry(p):
    d = {"name": "Asmr" if uri(p) == ROOT else os.path.basename(p), "uri": uri(p)}
    if os.path.isdir(p):
        d["type"] = "vnd.android.document/directory"
    else:
        d["type"] = "application/octet-stream"
        d["length"] = os.path.getsize(p)
        d["last_modified"] = int(os.path.getmtime(p) * 1000)
    return d


def main(cmd, args):
    if cmd == "ls":
        p = path(args[0])
        print(json.dumps([entry(os.path.join(p, n)) for n in sorted(os.listdir(p))], ensure_ascii=False))
    elif cmd == "stat":
        print(json.dumps(entry(path(args[0])), ensure_ascii=False))
    elif cmd == "read":
        with open(path(args[0]), "rb") as f:
            shutil.copyfileobj(f, sys.stdout.buffer)
    elif cmd == "write":
        p, data = path(args[0]), sys.stdin.buffer.read()
        if os.environ.get("MOCK_SAF_NO_TRUNC") and os.path.exists(p):
            with open(p, "r+b") as f:
                f.write(data)
        else:
            with open(p, "wb") as f:
                f.write(data)
    elif cmd == "create":
        if args[0] == "-t":
            args = args[2:]
        parent, name = path(args[0]), args[1]
        target, n = os.path.join(parent, name), 1
        while os.path.exists(target):       # 안드로이드처럼 "이름 (1)" 로 만든다
            stem, ext = os.path.splitext(name)
            target = os.path.join(parent, "%s (%d)%s" % (stem, n, ext))
            n += 1
        open(target, "wb").close()
        print(uri(target))
    elif cmd == "rm":
        p = path(args[0])
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    elif cmd == "dirs":
        print(json.dumps([{"name": "Asmr", "uri": ROOT}]))
    else:
        sys.exit("mock: unknown " + cmd)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
