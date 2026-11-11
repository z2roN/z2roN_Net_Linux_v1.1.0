# flutter create 로 만들어진 리눅스 프로젝트에 z2roN Net 설정을 덧씌웁니다.
#  - 실행 파일 이름 z2roN_Net, 창 제목 "z2roN Net"
import os, re, sys

app = sys.argv[1]
cm = os.path.join(app, "linux", "CMakeLists.txt")
s = open(cm, encoding="utf-8").read()
s = re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "z2roN_Net")', s, count=1)
open(cm, "w", encoding="utf-8").write(s)

cc = os.path.join(app, "linux", "runner", "my_application.cc")
t = open(cc, encoding="utf-8").read()
t = t.replace('"z2ron_net"', '"z2roN Net"')
open(cc, "w", encoding="utf-8").write(t)
print("patched", app)
