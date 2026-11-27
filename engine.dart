// Mock Interview engine - interviewer.py ka seedha Dart port.
// Sawaal assets/bank.json se (32 roles, Python ke MODULES/BEHAVIOURAL se nikale gaye).
import 'dart:convert';
import 'dart:math';

class BankData {
  final List<String> levels, catOrder, missT, probeT, cues;
  final List<Map<String, dynamic>> behavioural;
  final Map<String, Role> modules;

  BankData._(
    this.levels,
    this.catOrder,
    this.missT,
    this.probeT,
    this.cues,
    this.behavioural,
    this.modules,
  );

  static BankData parse(String jsonText) {
    final d = jsonDecode(jsonText) as Map<String, dynamic>;
    List<String> ls(String k) =>
        (d[k] as List).map((e) => e.toString()).toList();
    final mods = <String, Role>{};
    (d['modules'] as Map<String, dynamic>).forEach((k, v) {
      final m = v as Map<String, dynamic>;
      mods[k] = Role(
        key: k,
        name: m['name'],
        cat: m['cat'] ?? '',
        aliases: (m['aliases'] as List).map((e) => e.toString()).toList(),
        questions: (m['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
    });
    return BankData._(
      ls('levels'),
      ls('cat_order'),
      ls('miss_t'),
      ls('probe_t'),
      ls('cues'),
      (d['behavioural'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      mods,
    );
  }

  /// Category ke order mein roles (Python app jaisa)
  List<Role> rolesInOrder() {
    final out = <Role>[];
    for (final c in catOrder) {
      out.addAll(modules.values.where((r) => r.cat == c));
    }
    out.addAll(modules.values.where((r) => !catOrder.contains(r.cat)));
    return out;
  }
}

class Role {
  final String key, name, cat;
  final List<String> aliases;
  final List<Map<String, dynamic>> questions;
  Role({
    required this.key,
    required this.name,
    required this.cat,
    required this.aliases,
    required this.questions,
  });
}

// ---------------- helpers (Python jaisa) ----------------
final _nonAlnum = RegExp(r'[^a-z0-9]+');
final _spaces = RegExp(r'\s+');

String norm(String t) =>
    t.toLowerCase().replaceAll(_nonAlnum, ' ').replaceAll(_spaces, ' ').trim();

bool hasKw(String ansN, String ansNs, String kw) {
  final k = norm(kw);
  final ks = k.replaceAll(' ', '');
  if (k.isEmpty) return false;
  if (ks.length <= 3) {
    // chhote words poore word ki tarah match hon ("po", "mm", "gr")
    return RegExp('(?<![a-z0-9])${RegExp.escape(k)}(?![a-z0-9])')
        .hasMatch(ansN);
  }
  return ansN.contains(k) || ansNs.contains(ks);
}

/// Python 3 round(): half ko even ki taraf (2.5 -> 2, 3.5 -> 4)
int pyRound(num x) {
  final f = x.floorToDouble();
  final diff = x - f;
  if (diff > 0.5) return f.toInt() + 1;
  if (diff < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

double pyRound1(double x) => pyRound(x * 10) / 10;

List<String> _groupFirsts(List<List<String>> groups) =>
    groups.map((g) => g.first).toList();

List<List<String>> groupsOf(Map<String, dynamic> q) => (q['groups'] as List)
    .map((g) => (g as List).map((e) => e.toString()).toList())
    .toList();

class Eval {
  final int score;
  final List<String> hit, miss;
  Eval(this.score, this.hit, this.miss);
}

Eval evaluate(Map<String, dynamic> q, String answer) {
  final n = norm(answer);
  final ns = n.replaceAll(' ', '');
  final hit = <String>[], miss = <String>[];
  for (final g in groupsOf(q)) {
    (g.any((k) => hasKw(n, ns, k)) ? hit : miss).add(g.first);
  }
  final groups = groupsOf(q).length;
  final need = q['behav'] == true ? 3 : max(2, pyRound(groups * 0.7));
  var score = min(10, pyRound(10 * hit.length / need));
  final words = n.isEmpty ? 0 : n.split(' ').length;
  if (words < 4) score = min(score, 1);
  return Eval(score, hit, miss);
}

String feedbackFor(int score, List<String> hit, List<String> miss) {
  if (score >= 7) return 'Good answer. You covered ${hit.take(3).join(', ')}.';
  if (score >= 4) {
    final h = hit.take(2).join(', ');
    return 'Partly right. You mentioned ${h.isEmpty ? 'a few points' : h}. You missed ${miss.take(3).join(', ')}.';
  }
  return 'That was incomplete. Key points to remember: ${miss.take(3).join(', ')}.';
}

String firstSentences(String text, [int n = 2]) =>
    text.split(RegExp(r'(?<=[.!?])\s+')).take(n).join(' ');

(int, String) evalFollowup(
  String answer,
  Map<String, dynamic> fu,
  String ideal,
  List<String> cues,
) {
  final n = norm(answer);
  final ns = n.replaceAll(' ', '');
  final words = n.isEmpty ? 0 : n.split(' ').length;
  if (fu['kind'] == 'miss') {
    final has = (fu['terms'] as List<String>).any((k) => hasKw(n, ns, k));
    if (has && words >= 10) return (8, 'Good. That fills the gap.');
    if (has) return (5, 'Right direction, but I wanted more detail.');
    return (
      2,
      'Not quite. Here is the short model answer. ${firstSentences(ideal)}',
    );
  }
  final c = cues.where((x) => hasKw(n, ns, x)).length;
  if (words >= 25 && c >= 2) {
    return (8, 'Good. That sounds like real project experience.');
  }
  if (words >= 12) {
    return (6, 'Okay. Next time add what you personally did and the result.');
  }
  return (3, 'Try to give a concrete project example with details.');
}

// ---------------- question picker ----------------
class Bank {
  final String key;
  final List<Map<String, dynamic>> qs;
  final Set<int> asked = {};
  int level;

  /// true = user ne level khud chuna: sirf usi level ke sawaal, difficulty nahi badlegi
  final bool fixed;
  int streak = 0;
  List<String> hist;
  final Random rnd;
  final void Function(List<String>)? saveHist;

  Bank(
    this.key,
    this.qs, {
    this.level = 0,
    this.fixed = false,
    List<String>? history,
    Random? random,
    this.saveHist,
  }) : hist = List.of(history ?? const []),
       rnd = random ?? Random() {
    final done = qs
        .map((q) => q['q'] as String)
        .toSet()
        .intersection(hist.toSet())
        .length;
    if (done >= 0.9 * qs.length) hist = []; // sab sun liya: naya cycle
  }

  /// Nazdeeki level pehle; pehle na sune hue sawaal pehle.
  Map<String, dynamic>? pick() {
    final seen = hist.toSet();
    final order = fixed
        ? [level]
        : ([0, 1, 2, 3]..sort((a, b) {
            final c = (a - level).abs().compareTo((b - level).abs());
            return c != 0 ? c : a.compareTo(b);
          }));
    for (final needFresh in [true, false]) {
      for (final lvl in order) {
        final pool = [
          for (var i = 0; i < qs.length; i++)
            if (qs[i]['lvl'] == lvl &&
                !asked.contains(i) &&
                (!needFresh || !seen.contains(qs[i]['q'])))
              i,
        ];
        if (pool.isNotEmpty) {
          final i = pool[rnd.nextInt(pool.length)];
          asked.add(i);
          hist.add(qs[i]['q']);
          if (hist.length > 200) hist = hist.sublist(hist.length - 200);
          saveHist?.call(hist);
          return qs[i];
        }
      }
    }
    return null;
  }

  /// Difficulty badle toh chhota spoken remark.
  String adjust(int score) {
    if (fixed) return '';
    if (score >= 7) {
      streak++;
      if (streak >= 2 && level < 3) {
        level++;
        streak = 0;
        return 'You are doing well, so let me raise the difficulty.';
      }
    } else if (score <= 3) {
      streak = 0;
      if (level > 0) {
        level--;
        return 'Let me step back to something a little more basic.';
      }
    } else {
      streak = 0;
    }
    return '';
  }
}

// ---------------- unlimited drill questions ----------------
/// Bank ke sawaal khatam hone ke baad unke concepts se naye sawaal (repeat nahi hote).
const drillOne = [
  'Explain {c} in the context of {t}. Where have you used it?',
  'What problems can happen with {c}, and how do you handle them?',
  'Give a real project example where {c} mattered for {t}.',
  'Quick one: what is {c}, and why is it important in {t}?',
  'How would you explain {c} to a junior colleague working on {t}?',
];
const drillTwo = [
  'How does {c} relate to {c2} when working on {t}?',
  'Compare {c} and {c2}. When would you choose one over the other?',
  'Walk me through how {c} and {c2} work together in {t}.',
];

class DrillGen {
  DrillGen(this.qs, this.rnd);
  final List<Map<String, dynamic>> qs;
  final Random rnd;
  final Set<String> used = {};
  final Set<String> usedText = {};

  /// level ke paas wala ek naya drill sawaal. null = sab combinations khatam.
  Map<String, dynamic>? next(int level, {bool only = false}) {
    final order = only
        ? [level]
        : ([0, 1, 2, 3]
            ..sort((a, b) => (a - level).abs().compareTo((b - level).abs())));
    for (final lvl in order) {
      final pool =
          qs.where((q) => q['lvl'] == lvl && groupsOf(q).length >= 2).toList()
            ..shuffle(rnd);
      for (final src in pool) {
        final gs = groupsOf(src);
        final idx = List.generate(gs.length, (i) => i)..shuffle(rnd);
        for (final i in idx) {
          final two = rnd.nextBool();
          final j = idx.firstWhere((x) => x != i);
          final tpls = two ? drillTwo : drillOne;
          for (var t = 0; t < tpls.length; t++) {
            final ti = (t + rnd.nextInt(tpls.length)) % tpls.length;
            final key = '${src['q']}#$i#${two ? j : -1}#$two#$ti';
            if (used.contains(key)) continue;
            used.add(key);
            final others = [
              for (var k = 0; k < gs.length; k++)
                if (k != i && k != j) gs[k],
            ]..shuffle(rnd);
            final groups = [gs[i], if (two) gs[j], ...others.take(two ? 1 : 2)];
            final q = tpls[ti]
                .replaceAll('{c2}', gs[j].first)
                .replaceAll('{c}', gs[i].first)
                .replaceAll('{t}', (src['topic'] as String).toLowerCase());
            if (!usedText.add(q)) continue;
            return {
              'lvl': src['lvl'],
              'topic': src['topic'],
              'q': q,
              'groups': groups,
              'ideal': src['ideal'],
              'drill': true,
            };
          }
        }
      }
    }
    return null;
  }
}

// ---------------- interview ----------------
class LogEntry {
  final String q, a, level, topic;
  final int? score;
  final String? ideal;
  LogEntry(this.q, this.a, this.score, this.level, this.topic, [this.ideal]);
}

class Report {
  final double overall;
  final String levelReached, verdict;
  final List<String> strengths, gaps, studyPlan;
  Report(
    this.overall,
    this.levelReached,
    this.strengths,
    this.gaps,
    this.studyPlan,
    this.verdict,
  );
}

class Interview {
  final BankData data;
  final String key, module;
  final int minutes;
  final DateTime Function() clock;
  final Random rnd;
  final List<String> history;
  final void Function(List<String>)? saveHist;
  late final DateTime t0 = clock();
  final List<LogEntry> log = [];
  Map<String, dynamic> cur = {};
  Bank? bank;
  int fuMade = 0;

  /// minutes <= 0 = unlimited (END dabane tak)
  bool get unlimited => minutes <= 0;
  late final int maxFu = unlimited ? 1 << 30 : max(3, minutes ~/ 4);
  late final DrillGen drills = DrillGen(data.modules[key]!.questions, rnd);
  int techSinceBehav = 0;

  /// User ka chuna hua level (0-3). null = Auto (pehle jaisa adaptive)
  final int? fixedLevel;

  /// Kitne sawaal (intro ke alawa). 0 = unlimited
  final int maxQuestions;

  /// Ab tak kitne main sawaal puche (follow-up nahi gine jaate)
  int asked = 0;
  bool behavDone = false;
  final List<String> behavAsked = [];

  Interview(
    this.data,
    this.key,
    this.minutes, {
    DateTime Function()? clock,
    Random? random,
    this.history = const [],
    this.saveHist,
    this.fixedLevel,
    this.maxQuestions = 0,
  }) : module = data.modules[key]!.name,
       clock = clock ?? DateTime.now,
       rnd = random ?? Random();

  double get elapsed => clock().difference(t0).inMilliseconds / 60000.0;

  String start() {
    t0; // timer shuru
    cur = {
      'q': 'Please introduce yourself and tell me about your experience.',
      'topic': 'Introduction',
      'level': 'beginner',
      'intro': true,
    };
    return 'Welcome to your $module mock interview. Let us begin. ${cur['q']}';
  }

  /// (bolne wala text, khatam?)
  (String, bool) turn(String answer, {bool skipped = false}) {
    final c = cur;
    if (c['followup'] != null) return _turnFollowup(answer, skipped);
    if (c['intro'] == true) {
      final yrs = RegExp(r'(\d+)\s*\+?\s*(?:years?|yrs?)')
          .allMatches(answer.toLowerCase())
          .map((m) => int.parse(m.group(1)!));
      final y = yrs.isEmpty ? 0 : yrs.reduce(max);
      bank = Bank(
        key,
        data.modules[key]!.questions,
        level: fixedLevel ?? (y <= 1 ? 0 : (y <= 4 ? 1 : 2)),
        fixed: fixedLevel != null,
        history: history,
        random: rnd,
        saveHist: saveHist,
      );
      log.add(LogEntry(c['q'], answer, null, 'beginner', 'Introduction'));
      return _next('Thank you. Let us start with the technical questions.');
    }
    final raw = c['_raw'] as Map<String, dynamic>;
    int score;
    List<String> hit = [], miss = [];
    String fb;
    if (skipped) {
      score = 0;
      fb = 'No problem, we will move on.';
    } else {
      final e = evaluate(raw, answer);
      score = e.score;
      hit = e.hit;
      miss = e.miss;
      fb = feedbackFor(score, hit, miss);
    }
    log.add(
      LogEntry(
        c['q'],
        skipped ? '(skipped)' : answer,
        score,
        c['level'],
        c['topic'],
        raw['ideal'],
      ),
    );
    final remark = raw['behav'] == true ? '' : bank!.adjust(score);
    final fu = skipped ? null : _followup(c, score, hit, miss);
    if (fu != null) {
      cur = fu;
      return ('$fb ${fu['q']}'.trim(), false);
    }
    return _next('$fb $remark'.trim());
  }

  Map<String, dynamic>? _followup(
    Map<String, dynamic> c,
    int score,
    List<String> hit,
    List<String> miss,
  ) {
    final raw = c['_raw'] as Map<String, dynamic>;
    if (raw['behav'] == true ||
        fuMade >= maxFu ||
        (!unlimited && elapsed >= minutes * 0.8)) {
      return null;
    }
    String kind, concept;
    if (score >= 4 && score <= 6 && miss.isNotEmpty) {
      kind = 'miss';
      final m3 = miss.take(3).toList();
      concept = m3[rnd.nextInt(m3.length)];
    } else if (score >= 7 && hit.isNotEmpty && rnd.nextDouble() < 0.5) {
      kind = 'probe';
      concept = hit[rnd.nextInt(hit.length)];
    } else {
      return null;
    }
    final group = groupsOf(raw)
        .firstWhere((g) => g.first == concept, orElse: () => [concept]);
    final t = kind == 'miss' ? data.missT : data.probeT;
    final q = t[rnd.nextInt(t.length)].replaceAll('{c}', concept);
    fuMade++;
    return {
      'q': q,
      'topic': c['topic'],
      'level': c['level'],
      '_raw': raw,
      'followup': {'kind': kind, 'concept': concept, 'terms': group},
    };
  }

  (String, bool) _turnFollowup(String answer, bool skipped) {
    final c = cur;
    int score;
    String fb;
    if (skipped) {
      score = 0;
      fb = 'No problem.';
    } else {
      final r = evalFollowup(
        answer,
        Map<String, dynamic>.from(c['followup']),
        (c['_raw'] as Map)['ideal'],
        data.cues,
      );
      score = r.$1;
      fb = r.$2;
    }
    log.add(
      LogEntry(
        c['q'],
        skipped ? '(skipped)' : answer,
        score,
        c['level'],
        '${c['topic']} (follow-up)',
      ),
    );
    return _next(fb);
  }

  (String, bool) _next([String prefix = '']) {
    if (maxQuestions > 0 && asked >= maxQuestions) {
      return (
        '$prefix That was my last question. Thank you for your time.'.trim(),
        true,
      );
    }
    if (!unlimited && elapsed >= minutes) {
      return ('$prefix That is all the time we have.'.trim(), true);
    }
    if (unlimited) {
      // har 6 technical sawaal ke baad ek behavioural
      if (techSinceBehav >= 6) {
        final b = _behavioural(
          prefix,
          'Now a question about your work experience.',
        );
        if (b != null) {
          techSinceBehav = 0;
          return b;
        }
      }
    } else if (!behavDone && elapsed >= minutes * 0.75) {
      behavDone = true;
      final b = _behavioural(
        prefix,
        'Now a question about your work experience.',
      );
      if (b != null) return b;
    }
    // pehle asli bank ke sawaal, khatam ho jayein toh unlimited drill sawaal
    final q =
        bank!.pick() ??
        drills.next(bank!.level, only: bank!.fixed) ??
        drills.next(bank!.level);
    if (q == null) {
      if (!unlimited && elapsed < minutes * 0.95) {
        final out = _behavioural(
          prefix,
          'Let me ask you about your work experience.',
        );
        if (out != null) return out;
      }
      return ('$prefix That was my last question.'.trim(), true);
    }
    techSinceBehav++;
    asked++;
    cur = {
      'q': q['q'],
      'topic': q['topic'],
      'level': data.levels[q['lvl']],
      '_raw': q,
    };
    return ('$prefix ${q['q']}'.trim(), false);
  }

  (String, bool)? _behavioural(String prefix, String lead) {
    final left = data.behavioural
        .where((q) => !behavAsked.contains(q['q']))
        .toList();
    if (left.isEmpty) return null;
    final q = left[rnd.nextInt(left.length)];
    asked++;
    behavAsked.add(q['q']);
    cur = {
      'q': q['q'],
      'topic': 'Behavioural',
      'level': 'behavioural',
      '_raw': q,
    };
    return ('$prefix $lead ${q['q']}'.trim(), false);
  }

  String hint() {
    final c = cur;
    if (c['followup'] != null) {
      return 'Start with what ${(c['followup'] as Map)['concept']} is, then say where it is used.';
    }
    if (c['_raw'] != null) {
      return 'Think about ${_groupFirsts(groupsOf(c['_raw'])).take(2).join(' and ')}.';
    }
    return 'Take your time and start with the basics.';
  }

  Report finish() {
    final scored = log.where((x) => x.score != null).toList();
    final avg = scored.isEmpty
        ? 0.0
        : pyRound1(
            scored.map((x) => x.score!).reduce((a, b) => a + b) / scored.length,
          );
    final top = [
      for (final x in scored)
        if (x.score! >= 6 && data.levels.contains(x.level))
          data.levels.indexOf(x.level),
    ];
    List<String> topics(bool Function(int) f) =>
        (scored
                .where((x) => f(x.score!) && !x.topic.contains('follow-up'))
                .map((x) => x.topic)
                .toSet()
                .toList()
              ..sort())
            .take(4)
            .toList();
    return Report(
      avg,
      top.isEmpty ? 'beginner' : data.levels[top.reduce(max)],
      topics((s) => s >= 7),
      topics((s) => s <= 5),
      [
        for (final x in scored)
          if (x.score! <= 5 && (x.ideal ?? '').isNotEmpty)
            'Revise ${x.topic}: ${x.ideal}',
      ].take(4).toList(),
      avg >= 8
          ? 'Interview ready at this level.'
          : avg >= 6
          ? 'Close. Polish the gaps and you will be ready.'
          : 'Needs more preparation on the fundamentals.',
    );
  }

  String reportText(Report rep) {
    final now = clock();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final l = <String>[
      'MOCK INTERVIEW REPORT - $module',
      '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}, ${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}',
      'Duration: ${elapsed.round()} minutes | Questions answered: ${log.length}',
      'Overall score: ${rep.overall} / 10 | Level reached: ${rep.levelReached}',
      '',
      'Verdict: ${rep.verdict}',
      '',
      'STRENGTHS',
      ...(rep.strengths.isEmpty ? ['  -'] : rep.strengths.map((s) => '  - $s')),
      '',
      'GAPS',
      ...rep.gaps.map((s) => '  - $s'),
      '',
      'STUDY PLAN',
      ...rep.studyPlan.map((s) => '  - $s'),
      '',
      'TRANSCRIPT',
    ];
    for (var i = 0; i < log.length; i++) {
      final x = log[i];
      l.add('${i + 1}. [${x.level} | ${x.topic}] score: ${x.score}');
      l.add('   Q: ${x.q}');
      l.add('   A: ${x.a}');
      if ((x.ideal ?? '').isNotEmpty && x.score != null && x.score! <= 5) {
        l.add('   Model answer: ${x.ideal}');
      }
    }
    return l.join('\n');
  }
}
