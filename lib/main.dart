import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

/* ====================== palette ====================== */
const ink = Color(0xFF091A15);
const forest = Color(0xFF103127);
const forest2 = Color(0xFF0D271F);
const jade = Color(0xFF1C5341);
const gold = Color(0xFFC9A86A);
const gold2 = Color(0xFFE8CD8F);
const ivory = Color(0xFFF3EEE3);
const sage = Color(0xFF8AA094);
const paidC = Color(0xFF62BD8F);
const pendingC = Color(0xFFE0A85C);
const clay = Color(0xFFD68160);
const line = Color(0x29C9A86A);

/* ====================== text helpers ====================== */
TextStyle fr(double size, {FontWeight w = FontWeight.w400, Color color = ivory, double ls = 0}) =>
    GoogleFonts.fraunces(fontSize: size, fontWeight: w, color: color, letterSpacing: ls);
TextStyle jk(double size, {FontWeight w = FontWeight.w400, Color color = ivory, double ls = 0}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: color, letterSpacing: ls);

/* ====================== formatting ====================== */
String inr(num n) => '₹${NumberFormat.decimalPattern('en_IN').format(n.round())}';
String _two(int n) => n.toString().padLeft(2, '0');
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String monthKeyOf(DateTime d) => '${d.year}-${_two(d.month)}';
String monthLabel(String key) {
  final p = key.split('-');
  return '${_mon[int.parse(p[1]) - 1]} ${p[0]}';
}
String shiftMonth(String key, int delta) {
  final p = key.split('-');
  return monthKeyOf(DateTime(int.parse(p[0]), int.parse(p[1]) + delta, 1));
}
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
}
String uid() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

/* ====================== loan math (flat interest) ====================== */
Map<String, dynamic> computeLoan(Map loan, Map settings, [DateTime? asOf]) {
  asOf ??= DateTime.now();
  final principal = (loan['amount'] as num).toDouble();
  final rate = (loan['rate'] as num).toDouble();
  final months = (loan['months'] as num).toInt();
  final interest = principal * rate * months / 1200;
  final totalPayable = principal + interest;
  final emi = months > 0 ? totalPayable / months : 0.0;
  final payments = (loan['payments'] as List?) ?? const [];
  final paid = payments.fold<double>(0, (s, p) => s + (p['amount'] as num).toDouble());
  final remaining = max(0.0, totalPayable - paid);
  final dp = (loan['date'] as String).split('-');
  final start = DateTime(int.parse(dp[0]), int.parse(dp[1]), 1);
  int elapsed = (asOf.year - start.year) * 12 + (asOf.month - start.month);
  if (elapsed < 0) elapsed = 0;
  if (elapsed > months) elapsed = months;
  final expectedPaid = emi * elapsed;
  final behind = max(0.0, expectedPaid - paid);
  final behindMonths = emi > 0 ? (behind / emi + 0.001).floor() : 0;
  double penalty = 0;
  if (remaining > 0 && behindMonths > 0) {
    final pa = (settings['penaltyAmount'] as num).toDouble();
    penalty = settings['penaltyType'] == 'day' ? behindMonths * 30 * pa : behindMonths * pa;
  }
  final status = remaining <= 0 ? 'closed' : (behindMonths > 0 ? 'overdue' : 'ontrack');
  return {
    'principal': principal, 'interest': interest, 'totalPayable': totalPayable,
    'emi': emi, 'paid': paid, 'remaining': remaining, 'behindMonths': behindMonths,
    'penalty': penalty, 'status': status,
  };
}


bool isLoanArchived(Map loan) => loan['archived'] == true;

num loanInterestReceived(Map loan, Map settings) {
  final c = computeLoan(loan, settings);
  final paid = _toNum(c['paid']).toDouble();
  final totalPayable = _toNum(c['totalPayable']).toDouble();
  final interest = _toNum(c['interest']).toDouble();
  if (paid <= 0 || totalPayable <= 0 || interest <= 0) return 0;
  // Flat-interest EMI: received interest is counted proportionally from every payment.
  return min(interest, paid * interest / totalPayable);
}

num loanInterestDue(Map loan, Map settings) {
  final c = computeLoan(loan, settings);
  return max(0, _toNum(c['interest']) - loanInterestReceived(loan, settings));
}

/* ====================== seed ====================== */
Map<String, dynamic> seedData() {
  final names = [
    ['Dhrupal Virani', ''], ['Soham Khunt', ''], ['Krinsh Sojitra', ''],
    ['Raj Virani', ''], ['Raj Virani (2)', ''], ['Ruchit Vekariya', ''],
  ];
  final members = [for (final n in names) {'id': uid(), 'name': n[0], 'phone': n[1]}];
  final tm = monthKeyOf(DateTime.now());
  final contributions = {tm: <String, dynamic>{}};
  for (var i = 0; i < members.length; i++) {
    contributions[tm]![members[i]['id'] as String] = 'paid';
  }
  final start = DateTime.now();
  final s = monthKeyOf(DateTime(start.year, start.month - 3, 1));
  final loans = [
    {
      'id': uid(), 'memberId': members[0]['id'], 'amount': 20000, 'rate': 12,
      'months': 10, 'date': '$s-01',
      'payments': [
        {'id': uid(), 'date': '$s-05', 'amount': 2200},
        {'id': uid(), 'date': '${shiftMonth(s, 1)}-05', 'amount': 2200},
      ],
    }
  ];
  return {
    'settings': {'groupName': 'Snehal Bachat Group', 'monthly': 1000, 'penaltyAmount': 200, 'penaltyType': 'month'},
    'members': members, 'contributions': contributions, 'penalties': <String, dynamic>{},
    'yearlyAdjustments': <String, dynamic>{}, 'loans': loans,
  };
}

/* ====================== store ====================== */
class AppStore extends ChangeNotifier {
  Map<String, dynamic> data = {};
  static const _key = 'gloan_data_v1';
  static const _groupKey = 'gloan_group_code_v1';

  String groupCode = 'SB2026';
  bool cloudReady = false;
  bool cloudSaving = false;
  String cloudStatus = 'Local storage only';

  String adminPhone = '';
  bool roleLoading = false;
  String roleStatus = 'Phone login optional';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cloudSub;
  DocumentReference<Map<String, dynamic>>? _groupRef;
  bool _applyingRemote = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    groupCode = sanitizeGroupCode(p.getString(_groupKey) ?? 'SB2026');
    final raw = p.getString(_key);
    if (raw == null) {
      data = seedData();
      _normalize();
      await p.setString(_key, jsonEncode(data));
    } else {
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
        _normalize();
        await p.setString(_key, jsonEncode(data));
      } catch (_) {
        data = seedData();
        _normalize();
        await p.setString(_key, jsonEncode(data));
      }
    }
    await connectCloud(groupCode);
  }

  String sanitizeGroupCode(String value) {
    final cleaned = value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    return cleaned.isEmpty ? 'SB2026' : cleaned;
  }

  String normalizePhone(String value) {
    var v = value.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (v.startsWith('+')) return v;
    if (v.length == 10) return '+91$v';
    if (v.startsWith('91') && v.length == 12) return '+$v';
    return v;
  }

  String get currentPhone => normalizePhone(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  bool get isPhoneLoggedIn => currentPhone.isNotEmpty;
  bool get isAdmin => adminPhone.isNotEmpty && normalizePhone(adminPhone) == currentPhone;
  bool get canEditData => adminPhone.isEmpty || isAdmin;
  String get roleLabel {
    if (!isPhoneLoggedIn) return adminPhone.isEmpty ? 'Guest / setup pending' : 'Guest view-only';
    if (adminPhone.isEmpty) return 'Admin setup pending';
    return isAdmin ? 'Admin' : 'Member view-only';
  }

  void _readRoleFromDoc(Map<String, dynamic>? doc) {
    final value = doc?['adminPhone'];
    adminPhone = value is String ? normalizePhone(value) : '';
    if (adminPhone.isEmpty) {
      roleStatus = isPhoneLoggedIn ? 'No admin set yet. Login phone can become admin.' : 'Phone login required for admin setup.';
    } else {
      roleStatus = isAdmin ? 'Logged in as Admin' : 'Logged in as Member / view-only';
    }
  }

  Future<void> refreshRole() async {
    if (_groupRef == null) {
      roleStatus = 'Cloud group not connected';
      notifyListeners();
      return;
    }
    try {
      roleLoading = true;
      notifyListeners();
      final snap = await _groupRef!.get();
      _readRoleFromDoc(snap.data());
      roleLoading = false;
      notifyListeners();
    } catch (e) {
      roleLoading = false;
      roleStatus = 'Role check error: $e';
      notifyListeners();
    }
  }

  Future<void> ensureAdminForLoggedPhone() async {
    if (_groupRef == null || !isPhoneLoggedIn) return;
    final phone = currentPhone;
    try {
      final snap = await _groupRef!.get();
      final existing = snap.data()?['adminPhone'];
      if (existing is String && existing.trim().isNotEmpty) {
        adminPhone = normalizePhone(existing);
      } else {
        adminPhone = phone;
        await _groupRef!.set({
          'adminPhone': phone,
          'adminCreatedAt': FieldValue.serverTimestamp(),
          'adminUid': FirebaseAuth.instance.currentUser?.uid ?? '',
        }, SetOptions(merge: true));
      }
      roleStatus = isAdmin ? 'Logged in as Admin' : 'Logged in as Member / view-only';
      notifyListeners();
    } catch (e) {
      roleStatus = 'Admin role setup error: $e';
      notifyListeners();
    }
  }

  Future<void> logoutPhoneKeepCloud() async {
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      roleStatus = 'Logged out. Guest view-only if admin is set.';
      await connectCloud(groupCode);
    } catch (e) {
      roleStatus = 'Logout failed: $e';
      notifyListeners();
    }
  }

  void _normalize() {
    data['settings'] ??= {'groupName': 'My Group', 'monthly': 1000, 'penaltyAmount': 0, 'penaltyType': 'month'};
    final s = data['settings'] as Map;
    s['groupName'] ??= 'My Group';
    s['monthly'] ??= 1000;
    s['penaltyAmount'] ??= 0;
    s['penaltyType'] ??= 'month';
    data['members'] ??= [];
    data['contributions'] ??= {};
    data['penalties'] ??= {};
    data['yearlyAdjustments'] ??= {};
    data['loans'] ??= [];
  }

  Map<String, dynamic> _cleanForFirestore(Map<String, dynamic> value) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  Future<void> _persistLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(data));
    await p.setString(_groupKey, groupCode);
  }

  Future<void> _persist() async {
    await _persistLocal();
    await _persistCloud();
  }

  Future<void> _persistCloud() async {
    if (!cloudReady || _applyingRemote || _groupRef == null) return;
    try {
      cloudSaving = true;
      cloudStatus = 'Cloud sync saving... ($groupCode)';
      notifyListeners();
      await _groupRef!.set({
        'groupCode': groupCode,
        'appData': _cleanForFirestore(data),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
      }, SetOptions(merge: true));
      cloudStatus = 'Cloud sync active ($groupCode)';
    } catch (e) {
      cloudReady = false;
      cloudStatus = 'Cloud sync error: $e';
    } finally {
      cloudSaving = false;
      notifyListeners();
    }
  }

  Future<void> connectCloud(String code) async {
    groupCode = sanitizeGroupCode(code);
    await _persistLocal();

    if (Firebase.apps.isEmpty) {
      cloudReady = false;
      cloudStatus = 'Firebase not connected. Data is saved on this phone only.';
      notifyListeners();
      return;
    }

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      cloudStatus = 'Connecting cloud sync... ($groupCode)';
      notifyListeners();

      await _cloudSub?.cancel();
      _groupRef = FirebaseFirestore.instance.collection('groups').doc(groupCode);
      final snap = await _groupRef!.get();
      _readRoleFromDoc(snap.data());

      if (snap.exists && snap.data()?['appData'] is Map) {
        _applyingRemote = true;
        data = Map<String, dynamic>.from(snap.data()!['appData'] as Map);
        _normalize();
        await _persistLocal();
        _applyingRemote = false;
      } else {
        await _groupRef!.set({
          'groupCode': groupCode,
          'appData': _cleanForFirestore(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
        }, SetOptions(merge: true));
      }

      await ensureAdminForLoggedPhone();

      cloudReady = true;
      cloudStatus = 'Cloud sync active ($groupCode)';
      notifyListeners();

      _cloudSub = _groupRef!.snapshots().listen((snapshot) async {
        _readRoleFromDoc(snapshot.data());
        final remote = snapshot.data()?['appData'];
        if (remote is! Map) {
          notifyListeners();
          return;
        }
        _applyingRemote = true;
        data = Map<String, dynamic>.from(remote);
        _normalize();
        await _persistLocal();
        _applyingRemote = false;
        cloudReady = true;
        cloudStatus = 'Cloud sync active ($groupCode)';
        notifyListeners();
      }, onError: (Object e) {
        cloudReady = false;
        cloudStatus = 'Cloud sync error: $e';
        notifyListeners();
      });
    } catch (e) {
      _applyingRemote = false;
      cloudReady = false;
      cloudStatus = 'Cloud sync error: $e';
      notifyListeners();
    }
  }

  void update(void Function(Map<String, dynamic>) mut) {
    mut(data);
    _normalize();
    _persist();
    notifyListeners();
  }

  void replace(Map<String, dynamic> next) {
    data = next;
    _normalize();
    _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _cloudSub?.cancel();
    super.dispose();
  }

  Map get settings => data['settings'] as Map;
  List get members => data['members'] as List;
  Map get contributions => data['contributions'] as Map;
  Map get penalties => data['penalties'] as Map;
  Map get yearlyAdjustments => data['yearlyAdjustments'] as Map;
  List get loans => data['loans'] as List;
}

bool isContributionPaid(dynamic v) => v == 'paid' || (v is Map && v['status'] == 'paid');

num _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

String ym(int year, int month) => '$year-${_two(month)}';

num monthlyPenalty(String month, String memberId) {
  final root = store.data['penalties'];
  if (root is! Map) return 0;
  final mo = root[month];
  if (mo is! Map) return 0;
  return _toNum(mo[memberId]);
}


num monthPenaltyTotal(String month, {bool paidOnly = false}) {
  final root = store.data['penalties'];
  if (root is! Map) return 0;
  final mo = root[month];
  if (mo is! Map) return 0;
  final contribMo = (store.contributions[month] as Map?) ?? {};
  num total = 0;
  mo.forEach((memberId, value) {
    if (!paidOnly || isContributionPaid(contribMo[memberId])) total += _toNum(value);
  });
  return total;
}

num allCollectionPenaltyTotal({bool paidOnly = false}) {
  final root = store.data['penalties'];
  if (root is! Map) return 0;
  num total = 0;
  root.forEach((month, value) {
    if (value is Map) total += monthPenaltyTotal(month as String, paidOnly: paidOnly);
  });
  return total;
}

Map<String, dynamic> yearlyAdjustment(int year, String memberId) {
  final root = store.data['yearlyAdjustments'];
  if (root is! Map) return <String, dynamic>{};
  final yr = root['$year'];
  if (yr is! Map) return <String, dynamic>{};
  final row = yr[memberId];
  if (row is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(row);
}

num yearlyAdjustmentValue(int year, String memberId, String key) => _toNum(yearlyAdjustment(year, memberId)[key]);

num yearPenaltyTotal(int year, String memberId) {
  num total = 0;
  for (var i = 1; i <= 12; i++) {
    total += monthlyPenalty(ym(year, i), memberId);
  }
  return total;
}

num yearContributionTotal(int year, String memberId) {
  final monthly = _toNum(store.settings['monthly']);
  num total = 0;
  for (var i = 1; i <= 12; i++) {
    final mo = (store.contributions[ym(year, i)] as Map?) ?? {};
    if (isContributionPaid(mo[memberId])) total += monthly;
  }
  return total;
}


String penaltyNotes(int year, String memberId) {
  final notes = <String>[];
  for (var i = 1; i <= 12; i++) {
    final p = monthlyPenalty(ym(year, i), memberId);
    if (p > 0) notes.add('${p.round()}(${_mon[i - 1].toUpperCase()})');
  }
  return notes.isEmpty ? 'Penalty:' : 'Penalty:${notes.join(', ')}';
}

String _plainMoney(num n) => 'Rs.${NumberFormat.decimalPattern('en_IN').format(n.round())}';
String _paidText(bool paid) => paid ? 'Paid' : 'Pending';
String _percentText(num n) => n == 0 ? '-' : '${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)}%';

Map<String, num> dashboardTotals() {
  final s = store.settings;
  final monthly = _toNum(s['monthly']);
  num totalContrib = 0;
  num disbursed = 0;
  num repaid = 0;
  num interestExpected = 0;
  num interestReceived = 0;
  num loanPenalty = 0;
  num outstanding = 0;

  store.contributions.forEach((month, value) {
    if (value is Map) {
      value.forEach((memberId, status) {
        if (isContributionPaid(status)) {
          totalContrib += monthly;
          totalContrib += monthlyPenalty(month as String, memberId as String);
        }
      });
    }
  });

  for (final item in store.loans) {
    final loan = item as Map;
    final c = computeLoan(loan, s);
    disbursed += _toNum(c['principal']);
    repaid += _toNum(c['paid']);
    interestExpected += _toNum(c['interest']);
    interestReceived += loanInterestReceived(loan, s);
    if (!isLoanArchived(loan)) {
      loanPenalty += _toNum(c['penalty']);
      outstanding += _toNum(c['remaining']);
    }
  }

  final collectionPenalty = allCollectionPenaltyTotal();
  return {
    'cash': totalContrib + repaid - disbursed,
    'members': store.members.length,
    'loansOut': outstanding,
    'interestExpected': interestExpected,
    'interestReceived': interestReceived,
    'interestDue': max<num>(0, interestExpected - interestReceived),
    'penalty': loanPenalty + collectionPenalty,
    'collectionPenalty': collectionPenalty,
  };
}

String buildCurrentMonthShareText(String month) {
  final monthly = _toNum(store.settings['monthly']);
  final monthC = (store.contributions[month] as Map?) ?? {};
  final b = StringBuffer();
  num collected = 0;
  num pending = 0;

  b.writeln('COLLECTION - ${monthLabel(month)}');
  for (final mem in store.members) {
    final m = mem as Map;
    final id = m['id'] as String;
    final paid = isContributionPaid(monthC[id]);
    final penalty = monthlyPenalty(month, id);
    final amount = monthly + penalty;
    if (paid) {
      collected += amount;
    } else {
      pending += amount;
    }
    b.writeln('${m['name']}: ${_paidText(paid)} | Monthly ${_plainMoney(monthly)} | Penalty ${_plainMoney(penalty)} | Total ${_plainMoney(amount)}');
  }
  b.writeln('Collected: ${_plainMoney(collected)}');
  b.writeln('Pending: ${_plainMoney(pending)}');
  b.writeln('Total: ${_plainMoney(collected + pending)}');
  return b.toString();
}

String buildLoansShareText() {
  final b = StringBuffer();
  b.writeln('LOANS');
  if (store.loans.isEmpty) {
    b.writeln('No loans yet.');
    return b.toString();
  }
  for (final item in store.loans) {
    final loan = item as Map;
    final member = store.members.firstWhere((x) => x['id'] == loan['memberId'], orElse: () => {'name': '-'}) as Map;
    final c = computeLoan(loan, store.settings);
    final archived = isLoanArchived(loan);
    b.writeln('${member['name']} (${archived ? 'Paid history' : c['status']})');
    b.writeln('  Principal: ${_plainMoney(_toNum(c['principal']))}');
    b.writeln('  Interest: ${_plainMoney(_toNum(c['interest']))}');
    b.writeln('  Total payable: ${_plainMoney(_toNum(c['totalPayable']))}');
    b.writeln('  Paid: ${_plainMoney(_toNum(c['paid']))}');
    b.writeln('  Remaining: ${_plainMoney(_toNum(c['remaining']))}');
    b.writeln('  EMI: ${_plainMoney(_toNum(c['emi']))} | Rate: ${loan['rate']}% | Months: ${loan['months']}');
    b.writeln('');
  }
  return b.toString();
}

String buildVcYearShareText(int year) {
  final b = StringBuffer();
  final monthly = _toNum(store.settings['monthly']);
  num grandContribution = 0;
  num grandPenalty = 0;
  num grandTotal = 0;
  num grandInterestDue = 0;
  num grandInterestPaid = 0;

  b.writeln('VC [$year] YEAR REPORT');
  b.writeln('Monthly amount: ${_plainMoney(monthly)}');
  b.writeln('');

  for (final item in store.members) {
    final member = item as Map;
    final id = member['id'] as String;
    final contribution = yearContributionTotal(year, id);
    final penalty = yearPenaltyTotal(year, id);
    final vcPercent = yearlyAdjustmentValue(year, id, 'vcPercent');
    final vcDr = yearlyAdjustmentValue(year, id, 'vcDr');
    final vcCr = yearlyAdjustmentValue(year, id, 'vcCr');
    final interestDue = yearlyAdjustmentValue(year, id, 'interestDue');
    final interestPaid = yearlyAdjustmentValue(year, id, 'interestPaid');
    final percentile = yearlyAdjustmentValue(year, id, 'percentile');
    final total = contribution + penalty + vcCr - vcDr;

    grandContribution += contribution;
    grandPenalty += penalty;
    grandInterestDue += interestDue;
    grandInterestPaid += interestPaid;
    grandTotal += total;

    final monthVals = <String>[];
    for (var i = 1; i <= 12; i++) {
      final paid = isContributionPaid(((store.contributions[ym(year, i)] as Map?) ?? {})[id]);
      monthVals.add('${_mon[i - 1].toUpperCase()}:${paid ? monthly.round() : '-'}');
    }

    b.writeln(member['name']);
    b.writeln('  ${monthVals.join(' | ')}');
    b.writeln('  Penalty: ${_plainMoney(penalty)} | VC(%): ${_percentText(vcPercent)} | VC(DR): ${_plainMoney(vcDr)} | VC(CR): ${_plainMoney(vcCr)}');
    b.writeln('  Interest due: ${_plainMoney(interestDue)} | Interest paid: ${_plainMoney(interestPaid)} | Percentile: ${_percentText(percentile)}');
    b.writeln('  Total: ${_plainMoney(total)} | ${penaltyNotes(year, id)}');
    b.writeln('');
  }

  b.writeln('VC [$year] TOTAL');
  b.writeln('Contribution: ${_plainMoney(grandContribution)}');
  b.writeln('Penalty: ${_plainMoney(grandPenalty)}');
  b.writeln('Interest due: ${_plainMoney(grandInterestDue)}');
  b.writeln('Interest paid: ${_plainMoney(grandInterestPaid)}');
  b.writeln('Total: ${_plainMoney(grandTotal)}');
  return b.toString();
}

String buildFullShareText({int? year}) {
  final y = year ?? DateTime.now().year;
  final tm = monthKeyOf(DateTime.now());
  final totals = dashboardTotals();
  final b = StringBuffer();
  b.writeln('GROUP LOAN REPORT');
  b.writeln('${store.settings['groupName']}');
  b.writeln('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');
  b.writeln('');
  b.writeln('SUMMARY');
  b.writeln('Cash in hand: ${_plainMoney(_toNum(totals['cash']))}');
  b.writeln('Members: ${store.members.length}');
  b.writeln('Loans out: ${_plainMoney(_toNum(totals['loansOut']))}');
  b.writeln('Interest expected: ${_plainMoney(_toNum(totals['interestExpected']))}');
  b.writeln('Interest credit/received: ${_plainMoney(_toNum(totals['interestReceived']))}');
  b.writeln('Interest due: ${_plainMoney(_toNum(totals['interestDue']))}');
  b.writeln('Penalty accrued: ${_plainMoney(_toNum(totals['penalty']))}');
  b.writeln('');
  b.writeln(buildCurrentMonthShareText(tm));
  b.writeln('');
  b.writeln(buildLoansShareText());
  b.writeln('');
  b.writeln(buildVcYearShareText(y));
  return b.toString();
}

String _safePdfText(String value) {
  return value
      .replaceAll('₹', 'Rs.')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('•', '-')
      .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E]'), '');
}

String _safePdfFileName(String value) {
  final base = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return base.isEmpty ? 'group_loan_report' : base;
}

pw.Widget _pdfReportLine(String rawLine) {
  final line = _safePdfText(rawLine);
  if (line.trim().isEmpty) return pw.SizedBox(height: 6);

  final isMainHeading = line == line.toUpperCase() && line.length <= 42 && !line.contains(':');
  final isSubHeading = !line.startsWith('  ') && line.length <= 50 && !line.contains('|') && !line.contains(':') && !line.contains('Rs.');

  if (isMainHeading) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#103127'),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(line, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  return pw.Padding(
    padding: pw.EdgeInsets.only(left: line.startsWith('  ') ? 10 : 0, bottom: 3),
    child: pw.Text(
      line,
      style: pw.TextStyle(
        fontSize: isSubHeading ? 10.5 : 9.5,
        fontWeight: isSubHeading ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: PdfColor.fromHex('#091A15'),
      ),
    ),
  );
}

Future<File> createReportPdfFile({required String title, required String body, required String filePrefix}) async {
  final pdf = pw.Document();
  final safeTitle = _safePdfText(title);
  final safeBody = _safePdfText(body);
  final generatedAt = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey500))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(_safePdfText('${store.settings['groupName']}'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#103127'))),
              pw.SizedBox(height: 2),
              pw.Text(safeTitle, style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#C9A86A'), fontWeight: pw.FontWeight.bold)),
            ]),
            pw.Text('Generated: $generatedAt', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (context) => [
        pw.SizedBox(height: 12),
        ...safeBody.split('\n').map(_pdfReportLine),
      ],
    ),
  );

  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File('${dir.path}/${_safePdfFileName(filePrefix)}_$stamp.pdf');
  await file.writeAsBytes(await pdf.save(), flush: true);
  return file;
}

Future<void> sharePdfOnWhatsApp(BuildContext context, {required String title, required String body, required String filePrefix}) async {
  try {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF તૈયાર થઈ રહી છે...', style: jk(14, color: ink)), backgroundColor: gold2, behavior: SnackBarBehavior.floating),
      );
    }
    final file = await createReportPdfFile(title: title, body: body, filePrefix: filePrefix);
    await Share.shareXFiles([XFile(file.path)], subject: title);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF share failed. Please try again.', style: jk(14, color: ink)), backgroundColor: clay, behavior: SnackBarBehavior.floating),
      );
    }
  }
}

late AppStore store;

bool requireAdminAccess(BuildContext context) {
  if (store.canEditData) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Only Admin can add/edit/delete data. Please login with admin phone number.', style: jk(14, color: ink)),
      backgroundColor: gold2,
      behavior: SnackBarBehavior.floating,
    ),
  );
  return false;
}

Future<void> initFirebaseSafely() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebaseSafely();
  store = AppStore();
  await store.load();
  runApp(const GroupLoanApp());
}

/* ====================== app root ====================== */
class GroupLoanApp extends StatelessWidget {
  const GroupLoanApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Group Loan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: ink, useMaterial3: true),
      home: AnimatedBuilder(animation: store, builder: (_, __) => const HomeShell()),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const Dashboard(), const MembersPage(), const CollectionPage(), const LoansPage(), const SettingsPage()];
    return Scaffold(
      backgroundColor: ink,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1), radius: 1.1,
            colors: [Color(0x1AC9A86A), ink], stops: [0, 0.6],
          ),
        ),
        child: SafeArea(bottom: false, child: pages[tab]),
      ),
      bottomNavigationBar: _TabBar(tab: tab, onTap: (i) => setState(() => tab = i)),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTap;
  const _TabBar({required this.tab, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final items = [
      [Icons.cottage_outlined, 'Home'],
      [Icons.groups_outlined, 'Members'],
      [Icons.event_available_outlined, 'Collect'],
      [Icons.savings_outlined, 'Loans'],
      [Icons.more_horiz, 'More'],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: forest2,
        border: Border(top: BorderSide(color: line)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(items[i][0] as IconData, size: 23, color: tab == i ? gold2 : sage),
                  const SizedBox(height: 3),
                  Text(items[i][1] as String, style: jk(10.5, w: FontWeight.w500, color: tab == i ? gold2 : sage)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/* ====================== shared widgets ====================== */
BoxDecoration cardDeco() => BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [forest, forest2]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    );

class Seal extends StatelessWidget {
  final String text;
  final double size;
  const Seal(this.text, {this.size = 42, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [gold2, gold]),
      ),
      alignment: Alignment.center,
      child: Text(text, style: fr(size * 0.34, w: FontWeight.w500, color: ink)),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {this.size = 42, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [jade, forest2]),
        border: Border.all(color: line),
      ),
      alignment: Alignment.center,
      child: Text(initialsOf(name), style: jk(size * 0.33, w: FontWeight.w600, color: gold2)),
    );
  }
}

class Tile extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final VoidCallback? onTap;
  const Tile(this.label, this.value, {this.valueColor = ivory, this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: jk(11.5, color: sage))),
            if (onTap != null) const Icon(Icons.touch_app_outlined, color: sage, size: 14),
          ]),
          const SizedBox(height: 7),
          Text(value, style: fr(23, color: valueColor)),
        ],
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }
}

Widget statusPill(String status) {
  final map = {
    'ontrack': ['On track', paidC, const Color(0x2462BD8F)],
    'overdue': ['Overdue', clay, const Color(0x29D68160)],
    'closed': ['Closed', sage, const Color(0x248AA094)],
    'history': ['Paid history', gold2, const Color(0x22C9A86A)],
  };
  final m = map[status]!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: m[2] as Color, borderRadius: BorderRadius.circular(20)),
    child: Text(m[0] as String, style: jk(10.5, color: m[1] as Color)),
  );
}

Future<bool> confirmDialog(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: line)),
      content: Text(message, style: jk(15, color: ivory)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: jk(14, color: sage))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Confirm', style: jk(14, w: FontWeight.w600, color: clay))),
      ],
    ),
  );
  return r ?? false;
}

InputDecoration fieldDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: jk(15, color: sage),
      filled: true,
      fillColor: forest2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: gold)),
    );

Widget fieldLabel(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 7, top: 4),
      child: Text(s, style: jk(12, color: sage)),
    );

Widget primaryButton(String label, VoidCallback? onTap) => SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: jk(15, w: FontWeight.w700, color: ink)),
      ),
    );

Widget ghostButton(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(label, style: jk(13.5, w: FontWeight.w600, color: gold2)),
      ),
    );

Widget dangerButton(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0x1FD68160),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: const BorderSide(color: Color(0x4DD68160))),
        ),
        child: Text(label, style: jk(14, w: FontWeight.w600, color: clay)),
      ),
    );

void openSheet(BuildContext context, String title, Widget child) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF123127), ink]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 11, bottom: 6),
                decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: fr(23))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: sage, size: 20)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PageHead extends StatelessWidget {
  final String title, sub;
  final Widget? action;
  const PageHead(this.title, this.sub, {this.action, super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: fr(30)),
                Text(sub, style: jk(12.5, color: sage)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

Widget addButton(String label, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [gold2, gold]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(label, style: jk(13.5, w: FontWeight.w600, color: ink)),
      ),
    );

/* ====================== Dashboard ====================== */
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    final members = store.members;
    final tm = monthKeyOf(DateTime.now());
    final monthC = (store.contributions[tm] as Map?) ?? {};
    final paidCount = members.where((m) => isContributionPaid(monthC[m['id']])).length;
    final monthly = (s['monthly'] as num);

    double totalContrib = 0, disbursed = 0, repaid = 0, interestExp = 0, interestReceived = 0, loanPenalty = 0, outstanding = 0;
    store.contributions.forEach((k, mo) {
      final monthMap = mo as Map;
      monthMap.forEach((memberId, status) {
        if (isContributionPaid(status)) {
          totalContrib += monthly;
          totalContrib += monthlyPenalty(k as String, memberId as String).toDouble();
        }
      });
    });
    for (final l in store.loans) {
      final c = computeLoan(l, s);
      disbursed += c['principal'];
      repaid += c['paid'];
      interestExp += c['interest'];
      interestReceived += loanInterestReceived(l, s).toDouble();
      if (!isLoanArchived(l as Map)) {
        loanPenalty += c['penalty'];
        outstanding += c['remaining'];
      }
    }
    final collectionPenalty = allCollectionPenaltyTotal();
    final penalty = loanPenalty + collectionPenalty;
    final cash = totalContrib + repaid - disbursed;
    final activeLoans = store.loans.where((l) => !isLoanArchived(l as Map) && computeLoan(l, s)['remaining'] > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          children: [
            Seal(initialsOf(s['groupName'] as String)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GROUP LEDGER', style: jk(10.5, w: FontWeight.w600, color: gold, ls: 2.2)),
                  Text(s['groupName'] as String, style: fr(19, w: FontWeight.w500)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(20)),
              child: Text(monthLabel(tm), style: jk(12, color: gold2)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        // hero
        Container(
          padding: const EdgeInsets.only(bottom: 18),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CASH IN HAND', style: jk(11, color: sage, ls: 1.8)),
              const SizedBox(height: 6),
              Text(inr(cash), style: fr(50, w: FontWeight.w300)),
              Container(width: 48, height: 2, margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [gold, Colors.transparent]))),
              Text('Money in minus money out, across all time', style: jk(13, color: sage)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Tile('Members', '${members.length}')),
          const SizedBox(width: 12),
          Expanded(child: Tile('Loans out', inr(outstanding), valueColor: gold2)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Tile('Interest (expected)', inr(interestExp), valueColor: paidC,
              onTap: () => openSheet(context, 'Interest details', InterestDetailsSheet(expected: interestExp, received: interestReceived)))),
          const SizedBox(width: 12),
          Expanded(child: Tile('Penalty (accrued)', inr(penalty), valueColor: clay)),
        ]),
        const SizedBox(height: 14),
        // collection
        Container(
          padding: const EdgeInsets.all(18),
          decoration: cardDeco(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THIS MONTH', style: jk(10.5, w: FontWeight.w600, color: gold, ls: 2)),
                    Text('Collection', style: fr(20)),
                    const SizedBox(height: 4),
                    Text('${inr(paidCount * monthly)} of ${inr(members.length * monthly)}', style: jk(13, color: sage)),
                  ],
                ),
              ),
              SizedBox(
                width: 92, height: 92,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 92, height: 92,
                    child: CircularProgressIndicator(
                      value: members.isEmpty ? 0 : paidCount / members.length,
                      strokeWidth: 8, color: gold, backgroundColor: const Color(0x14FFFFFF),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$paidCount', style: fr(26)),
                    Text('of ${members.length}', style: jk(9.5, color: sage)),
                  ]),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: cardDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active loans', style: fr(20)),
              const SizedBox(height: 6),
              if (activeLoans.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No active loans yet.', style: jk(13.5, color: sage)))
              else
                ...activeLoans.take(3).map((l) {
                  final m = store.members.firstWhere((x) => x['id'] == l['memberId'], orElse: () => {'name': '-'});
                  final c = computeLoan(l, s);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Avatar(m['name'] as String, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['name'] as String, style: jk(15, w: FontWeight.w600)),
                          Text('${inr(c['principal'])} · ${l['rate']}% · ${l['months']} mo', style: jk(12.5, color: sage)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(inr(c['remaining']), style: fr(15.5)),
                        const SizedBox(height: 3),
                        statusPill(c['status'] as String),
                      ]),
                    ]),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class InterestDetailsSheet extends StatelessWidget {
  final num expected;
  final num received;
  const InterestDetailsSheet({required this.expected, required this.received, super.key});
  @override
  Widget build(BuildContext context) {
    final due = max(0, expected - received);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(15),
        decoration: cardDeco(),
        child: Column(children: [
          _row('Interest (expected)', inr(expected), paidC),
          const Divider(color: line, height: 22),
          _row('Interest credit / received', inr(received), gold2),
          const Divider(color: line, height: 22),
          _row('Interest due', inr(due), due > 0 ? pendingC : sage),
        ]),
      ),
      const SizedBox(height: 12),
      Text('Loan payment થાય એટલે received interest auto update થશે. Loan paid historyમાં move કરશો તો બાકી amount settlement તરીકે add થશે અને interest delete નહીં થાય.', style: jk(12.5, color: sage)),
    ]);
  }

  Widget _row(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: jk(13, color: sage))),
          Text(value, style: fr(18, color: color)),
        ],
      );
}

/* ====================== Members ====================== */
class MembersPage extends StatelessWidget {
  const MembersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final members = store.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHead('Members', '${members.length} in the circle',
            action: addButton('+ Add', () { if (!requireAdminAccess(context)) return; openSheet(context, 'Add member', const AddMemberForm()); })),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(color: line, height: 1),
            itemBuilder: (_, i) {
              final m = members[i];
              return InkWell(
                onTap: () => openSheet(context, m['name'] as String, MemberDetail(memberId: m['id'] as String)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(children: [
                    Avatar(m['name'] as String),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name'] as String, style: jk(15, w: FontWeight.w600)),
                        Text((m['phone'] as String?)?.isNotEmpty == true ? m['phone'] as String : 'No number', style: jk(12.5, color: sage)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, color: sage),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AddMemberForm extends StatefulWidget {
  const AddMemberForm({super.key});
  @override
  State<AddMemberForm> createState() => _AddMemberFormState();
}

class _AddMemberFormState extends State<AddMemberForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  @override
  void dispose() { name.dispose(); phone.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      fieldLabel('Full name'),
      TextField(controller: name, autofocus: true, style: jk(16), decoration: fieldDeco('e.g. Ramesh Agravat')),
      fieldLabel('Mobile number (optional)'),
      TextField(controller: phone, keyboardType: TextInputType.phone, style: jk(16), decoration: fieldDeco('99000 00000')),
      const SizedBox(height: 16),
      primaryButton('Add to group', () {
        if (!requireAdminAccess(context)) return;
        if (name.text.trim().isEmpty) return;
        store.update((d) => (d['members'] as List).add({'id': uid(), 'name': name.text.trim(), 'phone': phone.text.trim()}));
        Navigator.pop(context);
      }),
    ]);
  }
}

class MemberDetail extends StatefulWidget {
  final String memberId;
  const MemberDetail({required this.memberId, super.key});
  @override
  State<MemberDetail> createState() => _MemberDetailState();
}

class _MemberDetailState extends State<MemberDetail> {
  @override
  Widget build(BuildContext context) {
    final m = store.members.firstWhere((x) => x['id'] == widget.memberId, orElse: () => {'name': '—', 'phone': ''});
    final s = store.settings;
    final monthsPaid = <String>[];
    store.contributions.forEach((k, mo) {
      if (isContributionPaid((mo as Map)[widget.memberId])) monthsPaid.add(k as String);
    });
    monthsPaid.sort((a, b) => b.compareTo(a));
    final myLoans = store.loans.where((l) => l['memberId'] == widget.memberId).toList();
    final contributed = monthsPaid.length * (s['monthly'] as num);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Avatar(m['name'] as String, size: 54),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m['name'] as String, style: jk(16, w: FontWeight.w600)),
          Text((m['phone'] as String?)?.isNotEmpty == true ? m['phone'] as String : 'No number', style: jk(12.5, color: sage)),
        ]),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Tile('Contributed', inr(contributed), valueColor: paidC)),
        const SizedBox(width: 12),
        Expanded(child: Tile('Months paid', '${monthsPaid.length}')),
      ]),
      _sectionLabel('Loan history'),
      if (myLoans.isEmpty) Text('No loans taken.', style: jk(13.5, color: sage)),
      ...myLoans.map((l) {
        final c = computeLoan(l, s);
        final archived = isLoanArchived(l as Map);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inr(c['principal']), style: jk(15, w: FontWeight.w600)),
              Text('${l['rate']}% · ${l['months']} mo · ${monthLabel((l['date'] as String).substring(0, 7))}', style: jk(12.5, color: sage)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(archived ? 'Paid history' : '${inr(c['remaining'])} left', style: fr(15)),
              const SizedBox(height: 3),
              statusPill(archived ? 'history' : c['status'] as String),
            ]),
          ]),
        );
      }),
      _sectionLabel('Contribution history'),
      if (monthsPaid.isEmpty) Text('No contributions recorded yet.', style: jk(13.5, color: sage)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in monthsPaid)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0x17C9A86A), border: Border.all(color: line), borderRadius: BorderRadius.circular(20)),
            child: Text(monthLabel(k), style: jk(12, color: gold2)),
          ),
      ]),
      const SizedBox(height: 18),
      dangerButton('Remove member', () async {
        if (!requireAdminAccess(context)) return;
        if (await confirmDialog(context, 'Remove ${m['name']} and all their records?')) {
          store.update((d) {
            (d['members'] as List).removeWhere((x) => x['id'] == widget.memberId);
            (d['contributions'] as Map).forEach((k, mo) => (mo as Map).remove(widget.memberId));
            (d['penalties'] as Map).forEach((k, mo) => (mo as Map).remove(widget.memberId));
            (d['yearlyAdjustments'] as Map).forEach((k, yr) => (yr as Map).remove(widget.memberId));
            (d['loans'] as List).removeWhere((l) => l['memberId'] == widget.memberId);
          });
          if (context.mounted) Navigator.pop(context);
        }
      }),
    ]);
  }
}

Widget _sectionLabel(String s) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.toUpperCase(), style: jk(11, w: FontWeight.w600, color: gold, ls: 2)),
        const SizedBox(height: 8),
        const Divider(color: line, height: 1),
      ]),
    );

/* ====================== Collection ====================== */
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  String month = monthKeyOf(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    final monthly = s['monthly'] as num;
    final members = store.members;
    final monthC = (store.contributions[month] as Map?) ?? {};
    final paid = members.where((m) => isContributionPaid(monthC[m['id']])).length;
    final penaltyAmt = members.fold<num>(0, (sum, m) => sum + monthlyPenalty(month, m['id'] as String));
    final paidPenaltyAmt = members.fold<num>(0, (sum, m) {
      final id = m['id'] as String;
      return sum + (isContributionPaid(monthC[id]) ? monthlyPenalty(month, id) : 0);
    });
    final collectedAmt = paid * monthly + paidPenaltyAmt;
    final pendingAmt = (members.length - paid) * monthly + (penaltyAmt - paidPenaltyAmt);

    return Column(children: [
      PageHead('Collection', '${inr(monthly)} per member'),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => setState(() => month = shiftMonth(month, -1)), icon: const Icon(Icons.chevron_left, color: gold2)),
        SizedBox(width: 130, child: Text(monthLabel(month), textAlign: TextAlign.center, style: fr(19))),
        IconButton(onPressed: () => setState(() => month = shiftMonth(month, 1)), icon: const Icon(Icons.chevron_right, color: gold2)),
      ]),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: cardDeco(),
        child: Row(children: [
          _strip('Collected', inr(collectedAmt), paidC),
          _strip('Pending', inr(pendingAmt), pendingC),
          _strip('Penalty', inr(penaltyAmt), clay),
          _strip('Total', inr(members.length * monthly + penaltyAmt), ivory),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        child: ghostButton('Mark everyone paid', () {
          if (!requireAdminAccess(context)) return;
          store.update((d) {
            final contribs = d['contributions'] as Map;
            final mo = Map<String, dynamic>.from((contribs[month] as Map?) ?? {});
            for (final m in store.members) mo[m['id'] as String] = 'paid';
            contribs[month] = mo;
          });
          setState(() {});
        }),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: members.length,
          separatorBuilder: (_, __) => const Divider(color: line, height: 1),
          itemBuilder: (_, i) {
            final m = members[i];
            final isPaid = isContributionPaid(monthC[m['id']]);
            final pen = monthlyPenalty(month, m['id'] as String);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(children: [
                Avatar(m['name'] as String),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['name'] as String, style: jk(15, w: FontWeight.w600)),
                  Text(pen > 0 ? '${inr(monthly)} · Penalty ${inr(pen)}' : inr(monthly), style: jk(12.5, color: pen > 0 ? clay : sage)),
                ])),
                IconButton(
                  onPressed: () { if (!requireAdminAccess(context)) return; openSheet(context, '${m['name']} · ${monthLabel(month)}', CollectionEntryForm(memberId: m['id'] as String, month: month, onSaved: () => setState(() {}))); },
                  icon: Icon(Icons.edit_note_outlined, color: pen > 0 ? clay : sage, size: 22),
                ),
                GestureDetector(
                  onTap: () {
                    if (!requireAdminAccess(context)) return;
                    store.update((d) {
                      final contribs = d['contributions'] as Map;
                      final mo = Map<String, dynamic>.from((contribs[month] as Map?) ?? {});
                      mo[m['id']] = isContributionPaid(mo[m['id']]) ? 'pending' : 'paid';
                      contribs[month] = mo;
                    });
                    setState(() {});
                  },
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isPaid ? const Color(0x2962BD8F) : const Color(0x1AE0A85C),
                      border: Border.all(color: isPaid ? const Color(0x4D62BD8F) : line),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(isPaid ? 'Paid' : 'Pending', style: jk(12.5, w: FontWeight.w600, color: isPaid ? paidC : pendingC)),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _strip(String label, String value, Color c) => Expanded(
        child: Column(children: [
          Text(value, style: fr(17, color: c)),
          const SizedBox(height: 3),
          Text(label, style: jk(10.5, color: sage)),
        ]),
      );
}


class CollectionEntryForm extends StatefulWidget {
  final String memberId;
  final String month;
  final VoidCallback? onSaved;
  const CollectionEntryForm({required this.memberId, required this.month, this.onSaved, super.key});
  @override
  State<CollectionEntryForm> createState() => _CollectionEntryFormState();
}

class _CollectionEntryFormState extends State<CollectionEntryForm> {
  late bool paid;
  late TextEditingController penalty;

  @override
  void initState() {
    super.initState();
    final mo = (store.contributions[widget.month] as Map?) ?? {};
    paid = isContributionPaid(mo[widget.memberId]);
    final p = monthlyPenalty(widget.month, widget.memberId);
    penalty = TextEditingController(text: p > 0 ? '${p.round()}' : '');
  }

  @override
  void dispose() { penalty.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final monthly = _toNum(store.settings['monthly']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly amount', style: jk(12, color: sage)),
            const SizedBox(height: 4),
            Text(inr(monthly), style: fr(22, color: gold2)),
          ])),
          Switch(
            value: paid,
            activeColor: paidC,
            onChanged: (v) => setState(() => paid = v),
          ),
          Text(paid ? 'Paid' : 'Pending', style: jk(13, w: FontWeight.w600, color: paid ? paidC : pendingC)),
        ]),
      ),
      const SizedBox(height: 12),
      fieldLabel('Penalty for this month (₹)'),
      TextField(controller: penalty, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco('0')),
      const SizedBox(height: 16),
      primaryButton('Save entry', () {
        if (!requireAdminAccess(context)) return;
        store.update((d) {
          final contribs = d['contributions'] as Map;
          final mo = Map<String, dynamic>.from((contribs[widget.month] as Map?) ?? {});
          mo[widget.memberId] = paid ? 'paid' : 'pending';
          contribs[widget.month] = mo;

          final penalties = d['penalties'] as Map;
          final pmo = Map<String, dynamic>.from((penalties[widget.month] as Map?) ?? {});
          final v = num.tryParse(penalty.text.trim()) ?? 0;
          if (v > 0) {
            pmo[widget.memberId] = v;
          } else {
            pmo.remove(widget.memberId);
          }
          penalties[widget.month] = pmo;
        });
        widget.onSaved?.call();
        Navigator.pop(context);
      }),
    ]);
  }
}

/* ====================== Loans ====================== */
class LoansPage extends StatelessWidget {
  const LoansPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    final loans = store.loans;
    final active = loans.where((l) => !isLoanArchived(l as Map) && computeLoan(l, s)['remaining'] > 0).length;
    return Column(children: [
      PageHead('Loans', '$active active',
          action: addButton('+ Issue', () { if (!requireAdminAccess(context)) return; openSheet(context, 'Issue a loan', const AddLoanForm()); })),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          children: [
            if (loans.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('No loans yet.', style: jk(13.5, color: sage))),
            ...loans.map((l) {
              final m = store.members.firstWhere((x) => x['id'] == l['memberId'], orElse: () => {'name': '-'});
              final c = computeLoan(l, s);
              final archived = isLoanArchived(l as Map);
              final pct = (c['totalPayable'] as num) > 0 ? (c['paid'] as num) / (c['totalPayable'] as num) : 0.0;
              return GestureDetector(
                onTap: () => openSheet(context, m['name'] as String, LoanDetail(loanId: l['id'] as String)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(15),
                  decoration: cardDeco(),
                  child: Column(children: [
                    Row(children: [
                      Avatar(m['name'] as String, size: 38),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name'] as String, style: jk(15, w: FontWeight.w600)),
                        Text('${monthLabel((l['date'] as String).substring(0, 7))} · ${l['rate']}% · ${l['months']} mo', style: jk(12.5, color: sage)),
                      ])),
                      statusPill(archived ? 'history' : c['status'] as String),
                    ]),
                    const SizedBox(height: 13),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: pct.clamp(0, 1).toDouble(), minHeight: 6, color: gold, backgroundColor: const Color(0x14FFFFFF)),
                    ),
                    const SizedBox(height: 9),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('${inr(c['paid'])} paid', style: jk(12.5, color: sage)),
                      Text(archived ? 'Paid history' : '${inr(c['remaining'])} left', style: jk(12.5, color: sage)),
                    ]),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    ]);
  }
}

class AddLoanForm extends StatefulWidget {
  const AddLoanForm({super.key});
  @override
  State<AddLoanForm> createState() => _AddLoanFormState();
}

class _AddLoanFormState extends State<AddLoanForm> {
  String? memberId;
  final amount = TextEditingController();
  final rate = TextEditingController(text: '12');
  final months = TextEditingController(text: '10');
  @override
  void initState() {
    super.initState();
    if (store.members.isNotEmpty) memberId = store.members.first['id'] as String;
  }
  @override
  void dispose() { amount.dispose(); rate.dispose(); months.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final a = double.tryParse(amount.text) ?? 0;
    final r = double.tryParse(rate.text) ?? 0;
    final m = int.tryParse(months.text) ?? 0;
    final interest = a * r * m / 1200;
    final total = a + interest;
    final emi = m > 0 ? total / m : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      fieldLabel('Member'),
      Container(
        decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(13)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: memberId,
            isExpanded: true,
            dropdownColor: forest,
            style: jk(15),
            items: [for (final mem in store.members) DropdownMenuItem(value: mem['id'] as String, child: Text(mem['name'] as String, style: jk(15)))],
            onChanged: (v) => setState(() => memberId = v),
          ),
        ),
      ),
      fieldLabel('Loan amount'),
      TextField(controller: amount, keyboardType: TextInputType.number, style: jk(16), onChanged: (_) => setState(() {}), decoration: fieldDeco('20000')),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fieldLabel('Interest (annual %)'),
          TextField(controller: rate, keyboardType: TextInputType.number, style: jk(16), onChanged: (_) => setState(() {}), decoration: fieldDeco('12')),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fieldLabel('Duration (months)'),
          TextField(controller: months, keyboardType: TextInputType.number, style: jk(16), onChanged: (_) => setState(() {}), decoration: fieldDeco('10')),
        ])),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Align(alignment: Alignment.centerLeft, child: Text('Flat interest · amount × rate × months ÷ 1200', style: jk(11.5, color: gold))),
          const SizedBox(height: 12),
          _pv('Interest', inr(interest), ivory),
          const SizedBox(height: 8),
          _pv('Total payable', inr(total), ivory),
          const SizedBox(height: 8),
          _pv('Monthly EMI', inr(emi), gold2),
        ]),
      ),
      const SizedBox(height: 16),
      primaryButton('Issue loan', () {
        if (!requireAdminAccess(context)) return;
        if (memberId == null || (double.tryParse(amount.text) ?? 0) <= 0) return;
        store.update((d) => (d['loans'] as List).add({
              'id': uid(), 'memberId': memberId, 'amount': double.parse(amount.text),
              'rate': double.tryParse(rate.text) ?? 0, 'months': int.tryParse(months.text) ?? 1,
              'date': '${monthKeyOf(DateTime.now())}-01', 'payments': [],
            }));
        Navigator.pop(context);
      }),
    ]);
  }

  Widget _pv(String k, String v, Color c) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: jk(14, color: sage)),
        Text(v, style: fr(18, color: c)),
      ]);
}

class LoanDetail extends StatefulWidget {
  final String loanId;
  const LoanDetail({required this.loanId, super.key});
  @override
  State<LoanDetail> createState() => _LoanDetailState();
}

class _LoanDetailState extends State<LoanDetail> {
  final payAmt = TextEditingController();
  @override
  void dispose() { payAmt.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final loan = store.loans.firstWhere((l) => l['id'] == widget.loanId, orElse: () => {});
    if (loan.isEmpty) return const SizedBox.shrink();
    final s = store.settings;
    final c = computeLoan(loan, s);
    final archived = isLoanArchived(loan as Map);

    void record(double v) {
      if (!requireAdminAccess(context)) return;
      if (v <= 0) return;
      store.update((d) {
        final l = (d['loans'] as List).firstWhere((x) => x['id'] == widget.loanId);
        (l['payments'] as List).add({'id': uid(), 'date': '${monthKeyOf(DateTime.now())}-01', 'amount': v});
      });
      payAmt.clear();
      setState(() {});
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('REMAINING TO PAY', style: jk(11, color: sage, ls: 1.6)),
      const SizedBox(height: 4),
      Text(inr(c['remaining']), style: fr(44, w: FontWeight.w300)),
      Container(width: 48, height: 2, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [gold, Colors.transparent]))),
      Text('${inr(c['paid'])} of ${inr(c['totalPayable'])} paid', style: jk(13, color: sage)),
      if (archived) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0x22C9A86A), border: Border.all(color: line), borderRadius: BorderRadius.circular(13)),
          child: Text('This loan is moved to paid history. Payment and interest are still counted in dashboard.', style: jk(12.5, color: gold2)),
        ),
      ],
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.7, mainAxisSpacing: 1, crossAxisSpacing: 1,
        children: [
          _kv('Principal', inr(c['principal']), ivory),
          _kv('Interest rate', '${loan['rate']}% / yr', ivory),
          _kv('Interest', inr(c['interest']), ivory),
          _kv('Duration', '${loan['months']} months', ivory),
          _kv('Monthly EMI', inr(c['emi']), gold2),
          _kv('Total payable', inr(c['totalPayable']), ivory),
          _kv('Started', monthLabel((loan['date'] as String).substring(0, 7)), ivory),
          _kv('Penalty', inr(c['penalty']), (c['penalty'] as num) > 0 ? clay : ivory),
        ],
      ),
      if (c['status'] == 'overdue')
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0x1FD68160), border: Border.all(color: const Color(0x47D68160)), borderRadius: BorderRadius.circular(13)),
          child: Text('${c['behindMonths']} EMI(s) behind. Penalty of ${inr(c['penalty'])} has accrued at ${inr(s['penaltyAmount'])}/${s['penaltyType']}.', style: jk(13, color: clay)),
        ),
      if (!archived) ...[
        _sectionLabel('Record a payment'),
        Row(children: [
          Expanded(child: TextField(controller: payAmt, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco(inr(c['emi'])))),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => record(double.tryParse(payAmt.text) ?? 0),
            style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: ink, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
            child: Text('Add', style: jk(14, w: FontWeight.w700, color: ink)),
          ),
        ]),
        const SizedBox(height: 10),
        ghostButton('Pay one EMI · ${inr(c['emi'])}', () => record((c['emi'] as num).toDouble())),
      ],
      _sectionLabel('Payment history'),
      if ((loan['payments'] as List).isEmpty) Text('No payments yet.', style: jk(13.5, color: sage)),
      ...((loan['payments'] as List).reversed.map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(monthLabel((p['date'] as String).substring(0, 7)), style: jk(14, color: sage)),
              Text('+ ${inr(p['amount'])}', style: fr(15, color: paidC)),
            ]),
          ))),
      const SizedBox(height: 16),
      if (!archived)
        dangerButton('Move to paid history', () async {
          if (!requireAdminAccess(context)) return;
          if (await confirmDialog(context, 'Move this loan to paid history? Remaining amount will be added as settlement payment, so interest/payment data will not be deleted.')) {
            store.update((d) {
              final l = (d['loans'] as List).firstWhere((x) => x['id'] == widget.loanId);
              final calc = computeLoan(l, d['settings'] as Map);
              final remaining = _toNum(calc['remaining']).toDouble();
              if (remaining > 0) {
                (l['payments'] as List).add({
                  'id': uid(),
                  'date': '${monthKeyOf(DateTime.now())}-01',
                  'amount': remaining,
                  'note': 'Settlement while moving to paid history',
                });
              }
              l['archived'] = true;
              l['closedAt'] = DateTime.now().toIso8601String();
            });
            if (context.mounted) Navigator.pop(context);
          }
        })
      else
        Text('Paid historyમાં હોવાથી આ loan dashboardની active loan listમાં નહીં દેખાય.', style: jk(12.5, color: sage)),
    ]);
  }

  Widget _kv(String k, String v, Color c) => Container(
        color: forest2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(k, style: jk(11, color: sage)),
          const SizedBox(height: 5),
          Text(v, style: fr(17, color: c)),
        ]),
      );
}


/* ====================== VC Year Report ====================== */
class YearlyReportPage extends StatefulWidget {
  const YearlyReportPage({super.key});
  @override
  State<YearlyReportPage> createState() => _YearlyReportPageState();
}

class _YearlyReportPageState extends State<YearlyReportPage> {
  int year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final members = store.members;
    num grandContribution = 0;
    num grandPenalty = 0;
    num grandTotal = 0;
    num grandInterestDue = 0;
    num grandInterestPaid = 0;

    for (final m in members) {
      final id = m['id'] as String;
      final contribution = yearContributionTotal(year, id);
      final penalty = yearPenaltyTotal(year, id);
      final vcDr = yearlyAdjustmentValue(year, id, 'vcDr');
      final vcCr = yearlyAdjustmentValue(year, id, 'vcCr');
      final interestDue = yearlyAdjustmentValue(year, id, 'interestDue');
      final interestPaid = yearlyAdjustmentValue(year, id, 'interestPaid');
      grandContribution += contribution;
      grandPenalty += penalty;
      grandInterestDue += interestDue;
      grandInterestPaid += interestPaid;
      grandTotal += contribution + penalty + vcCr - vcDr;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => setState(() => year--), icon: const Icon(Icons.chevron_left, color: gold2)),
        Text('VC [$year]', style: fr(23, color: gold2)),
        IconButton(onPressed: () => setState(() => year++), icon: const Icon(Icons.chevron_right, color: gold2)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Column(children: [
          Row(children: [
            Expanded(child: _miniTotal('Contribution', inr(grandContribution), paidC)),
            Expanded(child: _miniTotal('Penalty', inr(grandPenalty), clay)),
            Expanded(child: _miniTotal('Total', inr(grandTotal), gold2)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _miniTotal('Interest due', inr(grandInterestDue), pendingC)),
            Expanded(child: _miniTotal('Interest paid', inr(grandInterestPaid), paidC)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Member wise Excel-style report', style: jk(12, color: sage)),
      const SizedBox(height: 10),
      if (members.isEmpty) Text('No members available.', style: jk(13.5, color: sage)),
      for (final m in members)
        YearMemberCard(member: m as Map, year: year, onChanged: () => setState(() {})),
    ]);
  }

  Widget _miniTotal(String label, String value, Color color) => Column(children: [
        Text(value, textAlign: TextAlign.center, style: fr(16.5, color: color)),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, style: jk(10.5, color: sage)),
      ]);
}

class YearMemberCard extends StatelessWidget {
  final Map member;
  final int year;
  final VoidCallback onChanged;
  const YearMemberCard({required this.member, required this.year, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    final id = member['id'] as String;
    final monthly = _toNum(store.settings['monthly']);
    final contribution = yearContributionTotal(year, id);
    final penalty = yearPenaltyTotal(year, id);
    final vcPercent = yearlyAdjustmentValue(year, id, 'vcPercent');
    final vcDr = yearlyAdjustmentValue(year, id, 'vcDr');
    final vcCr = yearlyAdjustmentValue(year, id, 'vcCr');
    final interestDue = yearlyAdjustmentValue(year, id, 'interestDue');
    final interestPaid = yearlyAdjustmentValue(year, id, 'interestPaid');
    final percentile = yearlyAdjustmentValue(year, id, 'percentile');
    final total = contribution + penalty + vcCr - vcDr;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(member['name'] as String, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member['name'] as String, style: jk(15, w: FontWeight.w700)),
            Text(penaltyNotes(year, id), style: jk(11.5, color: penalty > 0 ? clay : sage)),
          ])),
          Text(inr(total), style: fr(18, color: gold2)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 1; i <= 12; i++)
            _monthChip(_mon[i - 1].toUpperCase(), isContributionPaid(((store.contributions[ym(year, i)] as Map?) ?? {})[id]) ? inr(monthly) : '-'),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.05,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          children: [
            _smallCell('Penalty', inr(penalty), penalty > 0 ? clay : ivory),
            _smallCell('VC(%)', vcPercent == 0 ? '-' : '${vcPercent.toStringAsFixed(vcPercent % 1 == 0 ? 0 : 2)}%', ivory),
            _smallCell('VC(DR)', vcDr == 0 ? '-' : inr(vcDr), clay),
            _smallCell('VC(CR)', vcCr == 0 ? '-' : inr(vcCr), paidC),
            _smallCell('Interest due', inr(interestDue), pendingC),
            _smallCell('Interest paid', interestPaid == 0 ? '-' : inr(interestPaid), paidC),
            _smallCell('Percentile', percentile == 0 ? '-' : '${percentile.toStringAsFixed(percentile % 1 == 0 ? 0 : 2)}%', ivory),
            _smallCell('Total', inr(total), gold2),
          ],
        ),
        const SizedBox(height: 12),
        ghostButton('Edit VC / Interest fields', () { if (!requireAdminAccess(context)) return; openSheet(context, '${member['name']} · VC [$year]', YearlyFieldsForm(memberId: id, year: year, onSaved: onChanged)); }),
      ]),
    );
  }

  Widget _monthChip(String label, String value) => Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(label, style: jk(9.5, color: sage)),
          const SizedBox(height: 3),
          Text(value, style: jk(11.5, w: FontWeight.w700, color: value == '-' ? sage : gold2)),
        ]),
      );

  Widget _smallCell(String k, String v, Color c) => Container(
        color: forest2,
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: jk(9.5, color: sage)),
          const SizedBox(height: 3),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: jk(11.5, w: FontWeight.w700, color: c)),
        ]),
      );
}

class YearlyFieldsForm extends StatefulWidget {
  final String memberId;
  final int year;
  final VoidCallback? onSaved;
  const YearlyFieldsForm({required this.memberId, required this.year, this.onSaved, super.key});
  @override
  State<YearlyFieldsForm> createState() => _YearlyFieldsFormState();
}

class _YearlyFieldsFormState extends State<YearlyFieldsForm> {
  late TextEditingController vcPercent, vcDr, vcCr, interestDue, interestPaid, percentile;

  @override
  void initState() {
    super.initState();
    final a = yearlyAdjustment(widget.year, widget.memberId);
    vcPercent = TextEditingController(text: _textValue(a['vcPercent']));
    vcDr = TextEditingController(text: _textValue(a['vcDr']));
    vcCr = TextEditingController(text: _textValue(a['vcCr']));
    interestDue = TextEditingController(text: _textValue(a['interestDue']));
    interestPaid = TextEditingController(text: _textValue(a['interestPaid']));
    percentile = TextEditingController(text: _textValue(a['percentile']));
  }

  String _textValue(dynamic v) {
    final n = _toNum(v);
    return n == 0 ? '' : '${n.round()}';
  }

  @override
  void dispose() {
    vcPercent.dispose(); vcDr.dispose(); vcCr.dispose(); interestDue.dispose(); interestPaid.dispose(); percentile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _numField('VC (%)', vcPercent, '0')),
        const SizedBox(width: 10),
        Expanded(child: _numField('Percentile', percentile, '0')),
      ]),
      Row(children: [
        Expanded(child: _numField('VC (DR)', vcDr, '0')),
        const SizedBox(width: 10),
        Expanded(child: _numField('VC (CR)', vcCr, '0')),
      ]),
      Row(children: [
        Expanded(child: _numField('Interest due', interestDue, '0')),
        const SizedBox(width: 10),
        Expanded(child: _numField('Interest paid', interestPaid, '0')),
      ]),
      const SizedBox(height: 16),
      primaryButton('Save VC fields', () {
        if (!requireAdminAccess(context)) return;
        store.update((d) {
          final root = d['yearlyAdjustments'] as Map;
          final yr = Map<String, dynamic>.from((root['${widget.year}'] as Map?) ?? {});
          yr[widget.memberId] = {
            'vcPercent': num.tryParse(vcPercent.text.trim()) ?? 0,
            'vcDr': num.tryParse(vcDr.text.trim()) ?? 0,
            'vcCr': num.tryParse(vcCr.text.trim()) ?? 0,
            'interestDue': num.tryParse(interestDue.text.trim()) ?? 0,
            'interestPaid': num.tryParse(interestPaid.text.trim()) ?? 0,
            'percentile': num.tryParse(percentile.text.trim()) ?? 0,
          };
          root['${widget.year}'] = yr;
        });
        widget.onSaved?.call();
        Navigator.pop(context);
      }),
    ]);
  }

  Widget _numField(String label, TextEditingController c, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        fieldLabel(label),
        TextField(controller: c, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco(hint)),
      ]);
}


/* ====================== Phone Login / Roles ====================== */
class PhoneLoginCard extends StatefulWidget {
  const PhoneLoginCard({super.key});
  @override
  State<PhoneLoginCard> createState() => _PhoneLoginCardState();
}

class _PhoneLoginCardState extends State<PhoneLoginCard> {
  late TextEditingController phone;
  final otp = TextEditingController();
  String verificationId = '';
  bool codeSent = false;
  bool loading = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    phone = TextEditingController(text: store.currentPhone.isNotEmpty ? store.currentPhone : '+91');
  }

  @override
  void dispose() {
    phone.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final normalized = store.normalizePhone(phone.text);
    if (!normalized.startsWith('+') || normalized.length < 11) {
      setState(() => message = 'Please enter valid phone number with country code, e.g. +919999999999');
      return;
    }
    setState(() { loading = true; message = 'Sending OTP...'; });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            await store.connectCloud(store.groupCode);
            if (mounted) {
              setState(() { loading = false; message = 'Phone login successful.'; });
            }
          } catch (e) {
            if (mounted) setState(() { loading = false; message = 'Auto verification failed: $e'; });
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) setState(() { loading = false; message = e.message ?? 'OTP failed. Check Firebase Phone provider and SHA-1/SHA-256.'; });
        },
        codeSent: (String id, int? resendToken) {
          if (mounted) setState(() { loading = false; codeSent = true; verificationId = id; message = 'OTP sent to $normalized'; });
        },
        codeAutoRetrievalTimeout: (String id) {
          verificationId = id;
        },
      );
    } catch (e) {
      if (mounted) setState(() { loading = false; message = 'OTP send failed: $e'; });
    }
  }

  Future<void> _verifyOtp() async {
    if (verificationId.isEmpty || otp.text.trim().length < 4) {
      setState(() => message = 'Enter OTP first.');
      return;
    }
    setState(() { loading = true; message = 'Verifying OTP...'; });
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otp.text.trim());
      await FirebaseAuth.instance.signInWithCredential(credential);
      await store.connectCloud(store.groupCode);
      if (mounted) setState(() { loading = false; message = 'Phone login successful.'; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { loading = false; message = e.message ?? 'Invalid OTP.'; });
    } catch (e) {
      if (mounted) setState(() { loading = false; message = 'Login failed: $e'; });
    }
  }

  Future<void> _logout() async {
    setState(() { loading = true; message = 'Logging out...'; });
    await store.logoutPhoneKeepCloud();
    if (mounted) setState(() { loading = false; codeSent = false; otp.clear(); message = 'Phone logout complete.'; });
  }

  @override
  Widget build(BuildContext context) {
    final logged = store.isPhoneLoggedIn;
    final isAdmin = store.isAdmin;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(18),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(logged ? Icons.verified_user_outlined : Icons.phone_android_outlined, color: logged ? paidC : gold2),
          const SizedBox(width: 10),
          Expanded(child: Text('Phone Login & Role', style: fr(20))),
        ]),
        const SizedBox(height: 8),
        Text('Admin phone full access રાખશે. Other phone same Group Codeથી data જોઈ શકશે, પણ edit/delete માટે Admin login જોઈએ.', style: jk(13.5, color: sage)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(13)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Current role: ${store.roleLabel}', style: jk(13.5, w: FontWeight.w700, color: isAdmin ? paidC : gold2)),
            const SizedBox(height: 4),
            Text(logged ? 'Logged phone: ${store.currentPhone}' : 'Phone login not done', style: jk(12.5, color: sage)),
            if (store.adminPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Admin phone: ${store.adminPhone}', style: jk(12.5, color: sage)),
            ],
            const SizedBox(height: 4),
            Text(store.roleStatus, style: jk(12.5, color: isAdmin ? paidC : sage)),
          ]),
        ),
        const SizedBox(height: 12),
        fieldLabel('Mobile number'),
        TextField(controller: phone, keyboardType: TextInputType.phone, style: jk(16), decoration: fieldDeco('+919999999999')),
        const SizedBox(height: 10),
        if (codeSent) ...[
          fieldLabel('OTP'),
          TextField(controller: otp, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco('6 digit OTP')),
          const SizedBox(height: 10),
        ],
        if (message.isNotEmpty) ...[
          Text(message, style: jk(12.5, color: message.toLowerCase().contains('failed') || message.toLowerCase().contains('invalid') ? clay : paidC)),
          const SizedBox(height: 10),
        ],
        if (!logged) ...[
          primaryButton(loading ? 'Please wait...' : (codeSent ? 'Verify OTP & Login' : 'Send OTP'), loading ? null : (codeSent ? _verifyOtp : _sendOtp)),
          if (codeSent) ...[
            const SizedBox(height: 10),
            ghostButton('Resend OTP', loading ? () {} : _sendOtp),
          ],
        ] else ...[
          primaryButton(loading ? 'Please wait...' : 'Refresh Role', loading ? null : () async { await store.refreshRole(); if (mounted) setState(() {}); }),
          const SizedBox(height: 10),
          dangerButton('Logout phone login', loading ? () {} : _logout),
        ],
      ]),
    );
  }
}

/* ====================== Settings ====================== */
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController gname, monthly, penalty, groupCode;
  late String penaltyType;
  @override
  void initState() {
    super.initState();
    final s = store.settings;
    gname = TextEditingController(text: s['groupName'] as String);
    monthly = TextEditingController(text: '${s['monthly']}');
    penalty = TextEditingController(text: '${s['penaltyAmount']}');
    groupCode = TextEditingController(text: store.groupCode);
    penaltyType = s['penaltyType'] as String;
  }
  @override
  void dispose() { gname.dispose(); monthly.dispose(); penalty.dispose(); groupCode.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      const PageHead('More', 'Report, group rules & data'),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.all(18),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(store.cloudReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: store.cloudReady ? paidC : clay),
            const SizedBox(width: 10),
            Expanded(child: Text('Firebase Cloud Sync', style: fr(20))),
          ]),
          const SizedBox(height: 8),
          Text('Same Group Code use કરશો તો બધા phoneમાં same members, collection, penalty, loans, interest અને VC report sync થશે.', style: jk(13.5, color: sage)),
          const SizedBox(height: 12),
          fieldLabel('Group Code'),
          TextField(controller: groupCode, textCapitalization: TextCapitalization.characters, style: jk(16), decoration: fieldDeco('SB2026')),
          const SizedBox(height: 10),
          Text(store.cloudStatus, style: jk(12.5, color: store.cloudReady ? paidC : clay)),
          const SizedBox(height: 14),
          primaryButton(store.cloudSaving ? 'Syncing...' : 'Connect / Switch Group', store.cloudSaving ? null : () async {
            await store.connectCloud(groupCode.text);
            if (mounted) {
              groupCode.text = store.groupCode;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.cloudStatus, style: jk(14, color: ink)), backgroundColor: store.cloudReady ? gold2 : clay, behavior: SnackBarBehavior.floating));
              setState(() {});
            }
          }),
        ]),
      ),
      const SizedBox(height: 14),
      const PhoneLoginCard(),
      const SizedBox(height: 14),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.all(18),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VC Year Report', style: fr(20)),
          const SizedBox(height: 8),
          Text('Excel જેવી yearly sheet: Jan-Dec collection, penalty, VC(%), VC(DR), VC(CR), total અને interest fields.', style: jk(13.5, color: sage)),
          const SizedBox(height: 14),
          ghostButton('Open VC [Year] Report', () => openSheet(context, 'VC Year Report', const YearlyReportPage())),
          const SizedBox(height: 10),
          ghostButton('Share VC report PDF on WhatsApp', () async {
            final y = DateTime.now().year;
            await sharePdfOnWhatsApp(
              context,
              title: 'VC [$y] Report',
              body: buildVcYearShareText(y),
              filePrefix: 'VC_${y}_Report',
            );
          }),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.all(18),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fieldLabel('Group name'),
          TextField(controller: gname, style: jk(16), decoration: fieldDeco('Group name')),
          fieldLabel('Monthly contribution (₹)'),
          TextField(controller: monthly, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco('1000')),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              fieldLabel('Penalty amount (₹)'),
              TextField(controller: penalty, keyboardType: TextInputType.number, style: jk(16), decoration: fieldDeco('200')),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              fieldLabel('Penalty per'),
              Container(
                decoration: BoxDecoration(color: forest2, border: Border.all(color: line), borderRadius: BorderRadius.circular(13)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: penaltyType, isExpanded: true, dropdownColor: forest, style: jk(15),
                    items: [
                      DropdownMenuItem(value: 'month', child: Text('Month late', style: jk(15))),
                      DropdownMenuItem(value: 'day', child: Text('Day late', style: jk(15))),
                    ],
                    onChanged: (v) => setState(() => penaltyType = v ?? 'month'),
                  ),
                ),
              ),
            ])),
          ]),
          const SizedBox(height: 16),
          primaryButton('Save rules', () {
            if (!requireAdminAccess(context)) return;
            store.update((d) {
              final s = d['settings'] as Map;
              s['groupName'] = gname.text.trim().isEmpty ? 'My Group' : gname.text.trim();
              s['monthly'] = int.tryParse(monthly.text) ?? 1000;
              s['penaltyAmount'] = int.tryParse(penalty.text) ?? 0;
              s['penaltyType'] = penaltyType;
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rules saved', style: jk(14, color: ink)), backgroundColor: gold2, behavior: SnackBarBehavior.floating));
          }),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.all(18),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Data', style: fr(20)),
          const SizedBox(height: 8),
          Text('Everything is stored privately on this device. Reset restores the sample group; Clear empties it completely.', style: jk(13.5, color: sage)),
          const SizedBox(height: 14),
          ghostButton('Share all data PDF on WhatsApp', () async {
            await sharePdfOnWhatsApp(
              context,
              title: 'Full Group Loan Report',
              body: buildFullShareText(),
              filePrefix: 'Full_Group_Loan_Report',
            );
          }),
          const SizedBox(height: 10),
          ghostButton('Reset to sample data', () async {
            if (!requireAdminAccess(context)) return;
            if (await confirmDialog(context, 'Reset all data and restore the sample group? This cannot be undone.')) {
              store.replace(seedData());
            }
          }),
          const SizedBox(height: 10),
          dangerButton('Clear all data', () async {
            if (!requireAdminAccess(context)) return;
            if (await confirmDialog(context, 'Delete everything — all members, collections and loans? This leaves an empty group.')) {
              store.update((d) {
                d['members'] = [];
                d['contributions'] = {};
                d['penalties'] = {};
                d['yearlyAdjustments'] = {};
                d['loans'] = [];
              });
            }
          }),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
