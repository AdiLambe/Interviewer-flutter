// Mock Interview - Flutter app (32 job roles, offline, no AI, no key).
// Engine = interviewer.py ka Dart port (engine.dart), sawaal assets/bank.json mein.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';
import 'voice.dart';

const bg = Color(0xFF0E1321);
const card = Color(0xFF172036);
const card2 = Color(0xFF1E2A45);
const accent = Color(0xFF59BFFF);
const accentDark = Color(0xFF1F7AD9);
const textMain = Color(0xFFE6EAF2);
const muted = Color(0xFF94A0B8);
const good = Color(0xFF3DDC97);
const warn = Color(0xFFFFC857);
const bad = Color(0xFFFF6B6B);

Color scoreColor(num s) => s >= 7 ? good : (s >= 4 ? warn : bad);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (d) => Material(
        color: bg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('App mein error aaya - screenshot bhejo\n\n${d.exception}\n${d.stack}',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
  final bank = BankData.parse(await rootBundle.loadString('assets/bank.json'));
  final prefs = await SharedPreferences.getInstance();
  final voice = Voice();
  unawaited(voice.init());
  runApp(MockInterviewApp(app: AppCtx(bank, prefs, voice)));
}

/// Poore app ka shared data
class AppCtx {
  AppCtx(this.bank, this.prefs, this.voice);
  final BankData bank;
  final SharedPreferences prefs;
  final Voice voice;

  bool get voiceOn => prefs.getBool('voice_on') ?? true;
  set voiceOn(bool v) => prefs.setBool('voice_on', v);
  bool get autoListen => prefs.getBool('auto_listen') ?? false;
  set autoListen(bool v) => prefs.setBool('auto_listen', v);

  List<String> history(String key) => prefs.getStringList('hist_$key') ?? [];
  void saveHistory(String key, List<String> h) => prefs.setStringList('hist_$key', h);

  List<Map<String, dynamic>> pastReports() =>
      (prefs.getStringList('reports') ?? []).map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
  Future<void> addReport(Map<String, dynamic> r) async {
    final all = prefs.getStringList('reports') ?? [];
    all.insert(0, jsonEncode(r));
    await prefs.setStringList('reports', all.take(50).toList());
  }

  Future<void> say(String text) async {
    if (voiceOn) await voice.speak(text, lang: 'en-IN');
  }
}

class MockInterviewApp extends StatelessWidget {
  const MockInterviewApp({super.key, required this.app});
  final AppCtx app;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mock Interview',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: accent, surface: card),
        ),
        home: HomePage(app: app),
      );
}

// =====================================================================
//  Small UI helpers
// =====================================================================
Widget pill(String t, {Color color = accent, bool filled = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(t, style: TextStyle(color: filled ? bg : color, fontSize: 12, fontWeight: FontWeight.w700)),
    );

Widget panel({required Widget child, EdgeInsets? padding, Color color = card}) => Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: child,
    );

Widget primaryBtn(String text, VoidCallback? onTap, {IconData? icon, Color color = accentDark}) => SizedBox(
      height: 54,
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: card2,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        icon: Icon(icon ?? Icons.play_arrow_rounded),
        label: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
      ),
    );

IconData catIcon(String c) => switch (c) {
      'Testing and QA' => Icons.bug_report_outlined,
      'DevOps and Cloud' => Icons.cloud_outlined,
      'Backend' => Icons.dns_outlined,
      'Frontend' => Icons.web_outlined,
      'Databases and Data' => Icons.storage_outlined,
      'Middleware and Integration' => Icons.hub_outlined,
      'Product and Business' => Icons.trending_up,
      'SAP' => Icons.business_center_outlined,
      _ => Icons.work_outline,
    };

// =====================================================================
//  Home: role + duration
// =====================================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.app});
  final AppCtx app;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  String cat = 'All';
  Role? role;
  int minutes = 18;

  @override
  Widget build(BuildContext context) {
    final bank = widget.app.bank;
    final cats = ['All', ...bank.catOrder.where((c) => bank.modules.values.any((r) => r.cat == c))];
    final q = norm(query);
    final roles = bank.rolesInOrder().where((r) {
      if (cat != 'All' && r.cat != cat) return false;
      if (q.isEmpty) return true;
      return norm(r.name).contains(q) || r.aliases.any((a) => norm(a).contains(q));
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF1F4FA8), Color(0xFF0F7FB8)]),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('MOCK INTERVIEW',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12)),
                    const SizedBox(height: 6),
                    const Text('Practice like the real thing',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('${bank.modules.length} roles • offline • voice + score',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                IconButton(
                  tooltip: 'History',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(app: widget.app))),
                  icon: const Icon(Icons.history, color: Colors.white, size: 28),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => showModalBottomSheet(context: context, builder: (_) => SettingsSheet(app: widget.app)),
                  icon: const Icon(Icons.tune, color: Colors.white, size: 26),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                style: const TextStyle(color: textMain),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: muted),
                  hintText: 'Search role (Java, Playwright, SAP FICO...)',
                  hintStyle: const TextStyle(color: muted),
                  filled: true,
                  fillColor: card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: cat == c,
                        onSelected: (_) => setState(() => cat = c),
                        selectedColor: accentDark,
                        backgroundColor: card,
                        labelStyle: TextStyle(color: cat == c ? Colors.white : muted, fontWeight: FontWeight.w600),
                        side: BorderSide.none,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220, mainAxisExtent: 96, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: roles.length,
              itemBuilder: (_, i) {
                final r = roles[i];
                final on = role?.key == r.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => role = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: on ? accentDark.withValues(alpha: 0.25) : card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: on ? accent : Colors.transparent, width: 2),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(catIcon(r.cat), color: on ? accent : muted, size: 22),
                      const Spacer(),
                      Text(r.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: on ? Colors.white : textMain, fontWeight: FontWeight.w700)),
                      Text('${r.questions.length} questions', style: const TextStyle(color: muted, fontSize: 11)),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (roles.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Koi role nahi mila', style: TextStyle(color: muted))),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 170)),
        ]),
      ),
      bottomSheet: Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.timer_outlined, color: muted, size: 20),
              ),
              for (final m in const [10, 18, 25, 35])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => minutes = m),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: minutes == m ? accentDark : card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$m min',
                            style: TextStyle(
                                color: minutes == m ? Colors.white : muted, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            primaryBtn(
              role == null ? 'Choose a role' : 'Start ${role!.name}',
              role == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => InterviewPage(app: widget.app, role: role!, minutes: minutes)),
                      ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
//  Interview (chat style)
// =====================================================================
class Msg {
  final bool me;
  final String text;
  final int? score;
  Msg(this.me, this.text, [this.score]);
}

class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key, required this.app, required this.role, required this.minutes});
  final AppCtx app;
  final Role role;
  final int minutes;

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage> {
  late final Interview iv;
  final msgs = <Msg>[];
  final answer = TextEditingController();
  final scroll = ScrollController();
  Timer? tick;
  bool listening = false;
  bool speaking = false;
  bool finished = false;
  String hintText = '';

  @override
  void initState() {
    super.initState();
    final a = widget.app;
    iv = Interview(a.bank, widget.role.key, widget.minutes,
        history: a.history(widget.role.key), saveHist: (h) => a.saveHistory(widget.role.key, h));
    tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _bot(iv.start());
  }

  @override
  void dispose() {
    tick?.cancel();
    widget.app.voice.stop();
    super.dispose();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _bot(String text) async {
    setState(() {
      msgs.add(Msg(false, text));
      speaking = true;
    });
    _scrollDown();
    await widget.app.say(text);
    if (!mounted) return;
    setState(() => speaking = false);
    if (widget.app.autoListen && !finished) _listen();
  }

  Future<void> _listen() async {
    if (listening) return;
    await widget.app.voice.stop();
    setState(() => listening = true);
    final heard = await widget.app.voice.listen(localeId: 'en_IN');
    if (!mounted) return;
    setState(() {
      listening = false;
      if (heard != null && heard.trim().isNotEmpty) {
        answer.text = answer.text.trim().isEmpty ? heard : '${answer.text.trim()} $heard';
      }
    });
    if (heard == null && !widget.app.voice.canListen) {
      _snack('Mic nahi mila - jawab type karo (ya keyboard ka mic use karo)');
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  int? _lastScore() {
    for (final x in iv.log.reversed) {
      return x.score;
    }
    return null;
  }

  Future<void> _submit({bool skipped = false}) async {
    if (finished) return;
    final a = answer.text.trim();
    if (!skipped && a.isEmpty) {
      _snack('Jawab bolo/type karo, ya SKIP dabao');
      return;
    }
    await widget.app.voice.stop();
    final (msg, done) = iv.turn(a, skipped: skipped);
    setState(() {
      msgs.add(Msg(true, skipped ? '(skipped)' : a, _lastScore()));
      answer.clear();
      hintText = '';
    });
    if (done) {
      finished = true;
      await _bot(msg);
      _finish();
    } else {
      await _bot(msg);
    }
  }

  Future<void> _finish() async {
    finished = true;
    await widget.app.voice.stop();
    final rep = iv.finish();
    final text = iv.reportText(rep);
    await widget.app.addReport({
      'role': iv.module,
      'at': DateTime.now().millisecondsSinceEpoch,
      'score': rep.overall,
      'level': rep.levelReached,
      'text': text,
    });
    if (!mounted) return;
    unawaited(widget.app.say(
        'Interview complete. Your score is ${rep.overall} out of 10. ${rep.verdict}'));
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => ResultPage(app: widget.app, iv: iv, rep: rep, text: text)));
  }

  Future<void> _end() async {
    if (iv.log.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End interview?'),
        content: const Text('Abhi tak ke jawab se result banega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continue')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('End & see result')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final secs = (iv.elapsed * 60).floor();
    final left = math.max(0, widget.minutes * 60 - secs);
    final level = (iv.cur['level'] ?? 'beginner').toString();
    final progress = (secs / (widget.minutes * 60)).clamp(0.0, 1.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: bg,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.role.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text('${(left ~/ 60).toString().padLeft(2, '0')}:${(left % 60).toString().padLeft(2, '0')} left  •  ${iv.log.length} answered',
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 6), child: Center(child: pill(level))),
            TextButton(onPressed: _end, child: const Text('END', style: TextStyle(color: bad, fontWeight: FontWeight.w800))),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: card, color: accent),
          ),
        ),
        body: Column(children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(14),
              itemCount: msgs.length,
              itemBuilder: (_, i) => _bubble(msgs[i], i == msgs.length - 1),
            ),
          ),
          if (hintText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text('Hint: $hintText', style: const TextStyle(color: warn)),
            ),
          _composer(),
        ]),
      ),
    );
  }

  Widget _bubble(Msg m, bool last) {
    final maxW = MediaQuery.of(context).size.width * 0.82;
    return Align(
      alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.me ? accentDark : card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.me ? 16 : 4),
            bottomRight: Radius.circular(m.me ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!m.me)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.record_voice_over, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(speaking && last ? 'Interviewer is speaking...' : 'Interviewer',
                  style: const TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          if (!m.me) const SizedBox(height: 4),
          Text(m.text, style: const TextStyle(color: textMain, fontSize: 15, height: 1.35)),
          if (m.me && m.score != null) ...[
            const SizedBox(height: 6),
            pill('Score ${m.score}/10', color: scoreColor(m.score!), filled: true),
          ],
        ]),
      ),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(color: bg, border: Border(top: BorderSide(color: card2))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              _small(Icons.lightbulb_outline, 'Hint', () {
                final h = iv.hint();
                setState(() => hintText = h);
              }),
              _small(Icons.replay, 'Repeat', () => widget.app.say(msgs.lastWhere((m) => !m.me).text)),
              _small(Icons.skip_next, 'Skip', () => _submit(skipped: true)),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: answer,
                  minLines: 1,
                  maxLines: 5,
                  style: const TextStyle(color: textMain),
                  decoration: InputDecoration(
                    hintText: listening ? 'Listening... bolo' : 'Apna jawab bolo ya type karo',
                    hintStyle: TextStyle(color: listening ? good : muted),
                    filled: true,
                    fillColor: card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _round(listening ? Icons.graphic_eq : Icons.mic, listening ? good : card2, _listen),
              const SizedBox(width: 8),
              _round(Icons.send_rounded, accentDark, () => _submit()),
            ]),
          ]),
        ),
      );

  Widget _small(IconData i, String t, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: textMain,
              side: const BorderSide(color: card2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: finished ? null : onTap,
            icon: Icon(i, size: 18),
            label: Text(t),
          ),
        ),
      );

  Widget _round(IconData i, Color c, VoidCallback onTap) => Material(
        color: c,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: finished ? null : onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(i, color: Colors.white)),
        ),
      );
}

// =====================================================================
//  Result
// =====================================================================
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score});
  final double score;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        height: 150,
        child: CustomPaint(
          painter: _RingPainter(score / 10, scoreColor(score)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score', style: TextStyle(color: scoreColor(score), fontSize: 40, fontWeight: FontWeight.w900)),
              const Text('out of 10', style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.c);
  final double v;
  final Color c;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(8, 8, s.width - 16, s.height - 16);
    final base = Paint()
      ..color = card2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    final fg = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.app, required this.iv, required this.rep, required this.text});
  final AppCtx app;
  final Interview iv;
  final Report rep;
  final String text;

  Widget _section(String title, IconData icon, Color color, List<String> items, String empty) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
            const SizedBox(height: 8),
            if (items.isEmpty) Text(empty, style: const TextStyle(color: muted)),
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('•  ', style: TextStyle(color: color)),
                  Expanded(child: Text(s, style: const TextStyle(color: textMain, height: 1.35))),
                ]),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: bg, title: Text('Result • ${iv.module}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          panel(
            child: Column(children: [
              ScoreRing(score: rep.overall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                pill('Level: ${rep.levelReached}'),
                pill('${iv.log.length} answers', color: muted),
                pill('${iv.elapsed.round()} min', color: muted),
              ]),
              const SizedBox(height: 12),
              Text(rep.verdict,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scoreColor(rep.overall), fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          _section('STRENGTHS', Icons.thumb_up_alt_outlined, good, rep.strengths, 'Abhi koi strong topic nahi'),
          _section('AREAS TO IMPROVE', Icons.flag_outlined, warn, rep.gaps, 'Koi bada gap nahi'),
          _section('STUDY PLAN', Icons.menu_book_outlined, accent, rep.studyPlan, 'Koi specific study plan nahi'),
          const SizedBox(height: 12),
          panel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text('Full transcript', style: TextStyle(color: textMain, fontWeight: FontWeight.w700)),
              iconColor: accent,
              collapsedIconColor: muted,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final x in iv.log)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(x.topic, style: const TextStyle(color: accent, fontWeight: FontWeight.w700))),
                        if (x.score != null) pill('${x.score}/10', color: scoreColor(x.score!)),
                      ]),
                      Text('Q: ${x.q}', style: const TextStyle(color: textMain)),
                      Text('A: ${x.a}', style: const TextStyle(color: muted)),
                      if ((x.ideal ?? '').isNotEmpty && (x.score ?? 10) <= 5)
                        Text('Model answer: ${x.ideal}', style: const TextStyle(color: good, fontSize: 13)),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          primaryBtn('Copy full report', () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copy ho gaya')));
            }
          }, icon: Icons.copy_all, color: card2),
          const SizedBox(height: 10),
          primaryBtn('Back to home', () => Navigator.pop(context), icon: Icons.home_outlined),
        ]),
      );
}

// =====================================================================
//  History + settings
// =====================================================================
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.app});
  final AppCtx app;

  @override
  Widget build(BuildContext context) {
    final items = app.pastReports();
    return Scaffold(
      appBar: AppBar(backgroundColor: bg, title: const Text('Past interviews')),
      body: items.isEmpty
          ? const Center(child: Text('Abhi koi interview nahi diya', style: TextStyle(color: muted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = items[i];
                final at = DateTime.fromMillisecondsSinceEpoch(r['at']);
                final s = (r['score'] as num).toDouble();
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(backgroundColor: bg, title: Text(r['role'])),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(r['text'], style: const TextStyle(color: textMain, height: 1.4)),
                        ),
                      ),
                    ),
                  ),
                  child: panel(
                    child: Row(children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: scoreColor(s).withValues(alpha: 0.15),
                        child: Text('$s', style: TextStyle(color: scoreColor(s), fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['role'], style: const TextStyle(color: textMain, fontWeight: FontWeight.w700)),
                          Text('${at.day}/${at.month}/${at.year}  •  level ${r['level']}',
                              style: const TextStyle(color: muted, fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: muted),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.app});
  final AppCtx app;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  @override
  Widget build(BuildContext context) => Container(
        color: card,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              value: widget.app.voiceOn,
              onChanged: (v) => setState(() => widget.app.voiceOn = v),
              title: const Text('Interviewer voice'),
              subtitle: const Text('Sawaal awaaz mein bole'),
            ),
            SwitchListTile(
              value: widget.app.autoListen,
              onChanged: (v) => setState(() => widget.app.autoListen = v),
              title: const Text('Auto mic'),
              subtitle: const Text('Sawaal ke baad mic apne aap chalu'),
            ),
          ]),
        ),
      );
}
