// 리눅스에서 네트워크/컴퓨터 정보를 읽는 코드 (플러그인 없이 /proc, /sys, ip, iw, nmcli 등을 사용)
import 'dart:async';
import 'dart:io';

Future<String> run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args).timeout(const Duration(seconds: 4));
    return r.exitCode == 0 ? r.stdout.toString() : '';
  } catch (_) {
    return '';
  }
}

String _readFile(String path) {
  try {
    return File(path).readAsStringSync().trim();
  } catch (_) {
    return '';
  }
}

String? _osPretty() {
  for (final line in _readFile('/etc/os-release').split('\n')) {
    if (line.startsWith('PRETTY_NAME=')) return line.substring(12).replaceAll('"', '');
  }
  return null;
}

Future<Map<String, dynamic>> linuxInfo() async {
  final m = <String, dynamic>{};

  // ---- 내 컴퓨터 ----
  m['hostname'] = Platform.localHostname;
  m['osName'] = _osPretty() ?? 'Linux';
  m['kernel'] = (await run('uname', ['-r'])).trim();
  m['arch'] = (await run('uname', ['-m'])).trim();
  m['user'] = Platform.environment['USER'] ?? '';
  m['desktop'] = Platform.environment['XDG_CURRENT_DESKTOP'] ?? '';

  // ---- 기본 경로(게이트웨이, 사용 중인 인터페이스) ----
  String? gateway, iface;
  final route = await run('ip', ['-4', 'route', 'show', 'default']);
  final rm = RegExp(r'default(?: via (\S+))? dev (\S+)').firstMatch(route);
  if (rm != null) {
    gateway = rm.group(1);
    iface = rm.group(2);
  }
  if (iface == null) {
    // ip 명령이 없을 때: /proc/net/route (16진수, 리틀엔디안)
    for (final l in _readFile('/proc/net/route').split('\n').skip(1)) {
      final f = l.split(RegExp(r'\s+'));
      if (f.length > 3 && f[1] == '00000000') {
        iface = f[0];
        final g = int.tryParse(f[2], radix: 16) ?? 0;
        gateway = '${g & 0xff}.${(g >> 8) & 0xff}.${(g >> 16) & 0xff}.${(g >> 24) & 0xff}';
        break;
      }
    }
  }

  // ---- 모든 IPv4 ----
  final ifaces = <String>[];
  String? localIp;
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        if (a.isLoopback) continue;
        ifaces.add('${ni.name}: ${a.address}');
        if (ni.name == iface) localIp = a.address;
      }
    }
  } catch (_) {}
  int prefix = 24;
  if (iface != null) {
    final am = RegExp(r'inet (\d+\.\d+\.\d+\.\d+)/(\d+)').firstMatch(await run('ip', ['-4', '-o', 'addr', 'show', 'dev', iface]));
    if (am != null) {
      localIp ??= am.group(1);
      prefix = int.tryParse(am.group(2) ?? '') ?? 24;
    }
  }

  // ---- 연결 방식 ----
  String transport = 'none';
  if (iface != null) {
    if (Directory('/sys/class/net/$iface/wireless').existsSync() || Directory('/sys/class/net/$iface/phy80211').existsSync()) {
      transport = 'wifi';
    } else if (iface.startsWith('wwan') || iface.startsWith('ppp') || iface.startsWith('rmnet')) {
      transport = 'cellular';
    } else if (iface.startsWith('tun') || iface.startsWith('wg') || iface.startsWith('tap')) {
      transport = 'vpn';
    } else {
      transport = 'ethernet';
    }
  }

  // ---- Wi-Fi 상세 ----
  if (transport == 'wifi' && iface != null) {
    final iw = await run('iw', ['dev', iface, 'link']);
    final b = RegExp(r'Connected to ([0-9a-fA-F:]{17})').firstMatch(iw);
    if (b != null) m['bssid'] = b.group(1);
    final ss = RegExp(r'SSID: (.+)').firstMatch(iw);
    if (ss != null) m['ssid'] = ss.group(1)!.trim();
    final fr = RegExp(r'freq: (\d+)').firstMatch(iw);
    if (fr != null) m['freq'] = int.tryParse(fr.group(1)!);
    final sg = RegExp(r'signal: (-?\d+)').firstMatch(iw);
    if (sg != null) m['rssi'] = int.tryParse(sg.group(1)!);
    final rx = RegExp(r'rx bitrate: ([\d.]+)').firstMatch(iw);
    final tx = RegExp(r'tx bitrate: ([\d.]+)').firstMatch(iw);
    if (rx != null) m['rxSpeed'] = double.tryParse(rx.group(1)!)?.round();
    if (tx != null) m['txSpeed'] = double.tryParse(tx.group(1)!)?.round();
    if (m['rxSpeed'] != null || m['txSpeed'] != null) {
      m['linkSpeed'] = [m['rxSpeed'] ?? 0, m['txSpeed'] ?? 0].reduce((a, b) => (a as int) > (b as int) ? a : b);
    }
    if (m['ssid'] == null) {
      // iw 가 없을 때: NetworkManager / wireless-tools
      for (final l in (await run('nmcli', ['-t', '-f', 'active,ssid,rate', 'dev', 'wifi'])).split('\n')) {
        if (l.startsWith('yes:')) {
          final p = l.split(':');
          if (p.length >= 2) m['ssid'] = p[1];
          final r = RegExp(r'(\d+)').firstMatch(p.length >= 3 ? p[2] : '');
          if (r != null && m['linkSpeed'] == null) m['linkSpeed'] = int.tryParse(r.group(1)!);
          break;
        }
      }
      if (m['ssid'] == null) {
        final w = (await run('iwgetid', ['-r'])).trim();
        if (w.isNotEmpty) m['ssid'] = w;
      }
    }
  } else if (iface != null) {
    final sp = int.tryParse(_readFile('/sys/class/net/$iface/speed'));
    if (sp != null && sp > 0) m['linkSpeed'] = sp; // 유선 링크 속도(Mbps)
  }

  // ---- DNS ----
  final dns = <String>[];
  final rv = await run('resolvectl', ['dns']);
  for (final x in RegExp(r'(\d+\.\d+\.\d+\.\d+)').allMatches(rv)) {
    if (!dns.contains(x.group(1))) dns.add(x.group(1)!);
  }
  if (dns.isEmpty) {
    for (final l in _readFile('/etc/resolv.conf').split('\n')) {
      final x = RegExp(r'^nameserver\s+(\S+)').firstMatch(l);
      if (x != null && !dns.contains(x.group(1))) dns.add(x.group(1)!);
    }
  }

  m['transport'] = transport;
  m['localIp'] = localIp;
  m['prefix'] = prefix;
  m['gateway'] = gateway;
  m['iface'] = iface;
  m['dns'] = dns;
  m['ifaces'] = ifaces;
  return m;
}

/// ARP 표(/proc/net/arp)에서 IP → MAC
Map<String, String> arpTable() {
  final r = <String, String>{};
  for (final l in _readFile('/proc/net/arp').split('\n').skip(1)) {
    final f = l.split(RegExp(r'\s+'));
    if (f.length >= 4 && f[3] != '00:00:00:00:00:00') r[f[0]] = f[3];
  }
  return r;
}

List<String> _splitTerse(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  for (int i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '\\' && i + 1 < line.length) {
      sb.write(line[i + 1]);
      i++;
    } else if (c == ':') {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(c);
    }
  }
  out.add(sb.toString());
  return out;
}

/// 주변 Wi-Fi 목록 (NetworkManager 의 nmcli 사용)
Future<List<Map<String, dynamic>>> linuxWifiScan() async {
  const fields = 'IN-USE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY';
  var out = await run('nmcli', ['-t', '-f', fields, 'dev', 'wifi', 'list', '--rescan', 'yes']);
  if (out.trim().isEmpty) out = await run('nmcli', ['-t', '-f', fields, 'dev', 'wifi', 'list']); // 너무 자주 검색하면 이전 결과
  if (out.trim().isEmpty) throw 'nmcli 로 Wi-Fi 목록을 읽지 못했습니다 (NetworkManager 와 무선 어댑터가 필요합니다)';
  int? num(String v) => int.tryParse(RegExp(r'\d+').firstMatch(v)?.group(0) ?? '');
  final res = <Map<String, dynamic>>[];
  for (final l in out.split('\n')) {
    if (l.trim().isEmpty) continue;
    final f = _splitTerse(l);
    if (f.length < 8) continue;
    final pct = num(f[6]) ?? 0;
    res.add({
      'inUse': f[0].trim() == '*',
      'ssid': f[1],
      'bssid': f[2],
      'chan': num(f[3]),
      'freq': num(f[4]),
      'rate': num(f[5]),
      'pct': pct,
      'dbm': pct ~/ 2 - 100, // nmcli 는 0~100 값만 주므로 대략적인 dBm
      'sec': f[7].isEmpty ? '개방' : f[7],
    });
  }
  return res;
}
