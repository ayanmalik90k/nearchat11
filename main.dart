import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

const port = 8888;

// ---------- Networking: bina internet, sirf local hotspot par TCP socket ----------
class Net extends ChangeNotifier {
  String me = '';
  bool isHost = false;
  ServerSocket? _srv;
  Socket? _sock;
  final _clients = <Socket, String>{};
  final msgs = <Map>[];
  final stories = <Map>[];
  Set<String> online = {};

  static Future<String> myIp() async {
    final l = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return l.expand((i) => i.addresses).map((a) => a.address).join(', ');
  }

  Future<void> host(String name) async {
    me = name;
    isHost = true;
    online = {me};
    _srv = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _srv!.listen((c) {
      _read(c, (f) {
        if (f['t'] == 'hello') {
          _clients[c] = f['from'];
          _peers();
        } else {
          _handle(f);
          _relay(f, except: c);
        }
      }, onDone: () {
        _clients.remove(c);
        _peers();
      });
    });
    notifyListeners();
  }

  Future<void> join(String name, String ip) async {
    me = name;
    _sock = await Socket.connect(ip, port, timeout: const Duration(seconds: 6));
    _read(_sock!, _handle, onDone: () {
      online = {};
      notifyListeners();
    });
    _send(_sock!, {'t': 'hello', 'from': me});
  }

  void post(Map f) {
    final n = DateTime.now();
    f['from'] = me;
    f['time'] = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    _handle(f);
    isHost ? _relay(f) : _send(_sock!, f);
  }

  void _peers() {
    online = {me, ..._clients.values};
    _relay({'t': 'peers', 'list': online.toList()});
    notifyListeners();
  }

  void _relay(Map f, {Socket? except}) {
    for (final c in _clients.keys.where((c) => c != except)) {
      _send(c, f);
    }
  }

  void _handle(Map f) {
    switch (f['t']) {
      case 'peers':
        online = Set<String>.from(f['list']);
        break;
      case 'story':
        stories.add(f);
        break;
      default:
        msgs.add(f);
    }
    notifyListeners();
  }

  void _send(Socket s, Map f) {
    final j = utf8.encode(jsonEncode(f));
    s.add((ByteData(4)..setUint32(0, j.length)).buffer.asUint8List());
    s.add(j);
  }

  void _read(Socket s, void Function(Map) on, {void Function()? onDone}) {
    final buf = BytesBuilder();
    s.listen((d) {
      buf.add(d);
      var b = buf.takeBytes();
      while (b.length >= 4) {
        final n = ByteData.sublistView(b, 0, 4).getUint32(0);
        if (b.length < 4 + n) break;
        on(jsonDecode(utf8.decode(b.sublist(4, 4 + n))));
        b = b.sublist(4 + n);
      }
      buf.add(b);
    }, onDone: onDone, onError: (_) => onDone?.call());
  }
}

final net = Net();

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) {
    const seed = Color(0xFF0FA37F);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NearChat',
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const Setup(),
    );
  }
}

// ---------- Setup screen ----------
class Setup extends StatefulWidget {
  const Setup({super.key});
  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  final name = TextEditingController();
  final ip = TextEditingController(text: '192.168.43.1');
  String? err, myip;
  bool busy = false;

  Future<void> go(bool host) async {
    if (name.text.trim().isEmpty) return setState(() => err = 'Pehle apna naam likho');
    setState(() { busy = true; err = null; });
    try {
      host ? await net.host(name.text.trim()) : await net.join(name.text.trim(), ip.text.trim());
      myip = await Net.myIp();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Home(hostIp: host ? myip : null)));
    } catch (e) {
      setState(() { busy = false; err = 'Connect nahi hua. Hotspot on hai? IP sahi hai?'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('📡', style: TextStyle(fontSize: 54)),
                    Text('NearChat', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Text('Bina internet, aaspaas chat'),
                    const SizedBox(height: 18),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Tumhara naam', border: OutlineInputBorder())),
                    const SizedBox(height: 14),
                    FilledButton.icon(onPressed: busy ? null : () => go(true), icon: const Icon(Icons.wifi_tethering), label: const Text('Mai hotspot banata hu (Host)')),
                    const Divider(height: 30),
                    TextField(controller: ip, decoration: const InputDecoration(labelText: 'Host ka IP', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(onPressed: busy ? null : () => go(false), icon: const Icon(Icons.login), label: const Text('Hotspot se judo (Join)')),
                    if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: TextStyle(color: cs.error))),
                    if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Home: Chat, Stories, Online ----------
class Home extends StatefulWidget {
  final String? hostIp;
  const Home({super.key, this.hostIp});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final tc = TextEditingController();
  final sc = ScrollController();

  void sendText() {
    if (tc.text.trim().isEmpty) return;
    net.post({'t': 'msg', 'text': tc.text.trim()});
    tc.clear();
    Future.delayed(const Duration(milliseconds: 100), () => sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
  }

  Future<void> addStory() async {
    final t = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Story likho'),
      content: TextField(controller: t, autofocus: true, maxLines: 3),
      actions: [TextButton(onPressed: () { if (t.text.trim().isNotEmpty) net.post({'t': 'story', 'text': t.text.trim()}); Navigator.pop(context); }, child: const Text('Lagao'))],
    ));
  }

  void view(Map s) {
    final timer = Timer(const Duration(seconds: 5), () { if (mounted && Navigator.canPop(context)) Navigator.pop(context); });
    showDialog(context: context, builder: (_) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(child: Column(children: [
          TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(seconds: 5), builder: (_, v, __) => LinearProgressIndicator(value: v)),
          ListTile(leading: CircleAvatar(child: Text(s['from'][0])), title: Text(s['from'], style: const TextStyle(color: Colors.white)), subtitle: Text(s['time'], style: const TextStyle(color: Colors.white70))),
          Expanded(child: Center(child: s['data'] != null ? Image.memory(base64Decode(s['data'])) : Padding(padding: const EdgeInsets.all(28), child: Text(s['text'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))))),
        ])),
      ),
    )).then((_) => timer.cancel());
  }

  Widget bubble(Map m) {
    final mine = m['from'] == net.me;
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child)),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
          padding: const EdgeInsets.all(9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
          decoration: BoxDecoration(color: mine ? cs.primaryContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) Text(m['from'], style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 12)),
            if (m['t'] == 'img') ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(base64Decode(m['data']))) else Text(m['text'] ?? ''),
            Align(alignment: Alignment.centerRight, child: Text(m['time'], style: const TextStyle(fontSize: 10))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: net,
      builder: (_, __) {
        final pages = [chatTab(), storyTab(), onlineTab()];
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NearChat'),
              Text('${net.online.length} online${widget.hostIp != null ? ' · IP: ${widget.hostIp}' : ''}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          body: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(tab), child: pages[tab])),
          floatingActionButton: tab == 1 ? FloatingActionButton(onPressed: addStory, child: const Icon(Icons.edit)) : null,
          bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.motion_photos_on_outlined), selectedIcon: Icon(Icons.motion_photos_on), label: 'Stories'),
            NavigationDestination(icon: Icon(Icons.radar), label: 'Online'),
          ]),
        );
      },
    );
  }

  Widget chatTab() => Column(children: [
        Expanded(child: ListView(controller: sc, padding: const EdgeInsets.only(top: 8), children: net.msgs.where((m) => m['t'] != 'story').map(bubble).toList())),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: TextField(controller: tc, onSubmitted: (_) => sendText(), decoration: InputDecoration(hintText: 'Message likho…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)))),
            const SizedBox(width: 6),
            FloatingActionButton.small(onPressed: sendText, child: const Icon(Icons.send)),
          ]),
        ),
      ]);

  Widget storyTab() => net.stories.isEmpty
      ? const Center(child: Text('Abhi koi story nahi. ＋ dabao'))
      : ListView(children: net.stories.reversed.map((s) => ListTile(
            onTap: () => view(s),
            leading: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF0FA37F), Color(0xFF8A5CF6)])), child: CircleAvatar(child: Text(s['from'][0]))),
            title: Text(s['from']),
            subtitle: Text(s['time']),
          )).toList());

  Widget onlineTab() => ListView(children: net.online.map((n) => ListTile(
        leading: Stack(children: [CircleAvatar(child: Text(n[0])), const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 6, backgroundColor: Colors.greenAccent))]),
        title: Text(n == net.me ? '$n (tum)' : n),
        subtitle: const Text('online · nearby'),
      )).toList());
}
