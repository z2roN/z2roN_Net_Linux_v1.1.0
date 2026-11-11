# z2roN_Net Linux (네트워크 정보 보기) v1.1.0
리눅스 데스크톱용 네트워크 정보 보기 (Flutter, 플러그인 없음). Android 판(z2roN_Net)과 같은 화면입니다.

- 외부(공인) IP, 국가·통신사
- 연결 방식(유선/무선/모바일/VPN), Wi-Fi 이름(SSID)·BSSID·주파수·신호 세기, 연결 속도(링크 속도), 내 IP, DNS
- 게이트웨이(공유기) + [공유기 접속] 버튼(xdg-open 으로 브라우저 열기)
- 속도 측정: 다운로드 / 업로드 / 응답(핑) (Cloudflare 속도 측정 서버)
- 내 컴퓨터: 컴퓨터 이름, 운영체제(os-release), 커널/구조, 사용자, 데스크톱
- 같은 네트워크 기기 검색: IP, 이름, MAC(ARP), 종류·운영체제(포트와 ping TTL 로 추정)

## 실행
```
tar xzf z2roN_Net_Linux_v1.0.0.tar.gz
cd z2roN_Net
./z2roN_Net
```
실행 파일은 같은 폴더의 lib/ data/ 와 함께 있어야 하므로 폴더째 옮기세요. GTK3 가 설치된 데스크톱 리눅스에서 실행됩니다.

## 필요한 명령(없어도 실행은 되지만 해당 정보가 비어 있을 수 있음)
ip, iw 또는 nmcli(Wi-Fi 정보), ping(기기 검색 정확도), resolvectl(DNS)

## v1.1.0
- 주변 Wi-Fi 검색(nmcli): 이름(SSID), 신호 세기, 채널·주파수, 속도, 보안 방식, 연결된 Wi-Fi 표시

## v1.0.0
- 첫 버전 (실행 파일 이름 z2roN_Net)
