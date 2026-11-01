// Jalali (Solar Hijri) dates in Tehran time for the network-admin panel.
// Iran has had no daylight saving time since 2022, so Tehran is always UTC+03:30.

const Duration kTehranOffset = Duration(hours: 3, minutes: 30);

const _faMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', //
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];
const _enMonths = [
  'Farvardin', 'Ordibehesht', 'Khordad', 'Tir', 'Mordad', 'Shahrivar', //
  'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand',
];
// Indexed by DateTime.weekday (1 = Monday).
const _faWeekdays = [
  '',
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه'
];
const _enWeekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class JalaliDate {
  final int year, month, day;
  const JalaliDate(this.year, this.month, this.day);

  @override
  bool operator ==(Object other) =>
      other is JalaliDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// Wall-clock Tehran time of [t], as a UTC DateTime holding Tehran's fields.
DateTime toTehran(DateTime t) => t.toUtc().add(kTehranOffset);

JalaliDate toJalali(DateTime g) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy = g.year, gm = g.month, gd = g.day;
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 +
      365 * gy +
      (gy2 + 3) ~/ 4 -
      (gy2 + 99) ~/ 100 +
      (gy2 + 399) ~/ 400 +
      gd +
      gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = days < 186 ? 1 + days % 31 : 1 + (days - 186) % 30;
  return JalaliDate(jy, jm, jd);
}

String faDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return s.replaceAllMapped(
      RegExp(r'[0-9]'), (m) => fa[m.group(0)!.codeUnitAt(0) - 48]);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Formats server ISO-8601 UTC times for display in Tehran time.
class TehranFormat {
  final bool persian;
  const TehranFormat(this.persian);

  String _d(String s) => persian ? faDigits(s) : s;

  /// 1405/08/10
  String date(DateTime t) {
    final j = toJalali(toTehran(t));
    return _d('${j.year}/${_two(j.month)}/${_two(j.day)}');
  }

  /// 23:45
  String time(DateTime t) {
    final l = toTehran(t);
    return _d('${_two(l.hour)}:${_two(l.minute)}');
  }

  /// 1405/08/10 23:45
  String dateTime(DateTime t) => '${date(t)}  ${time(t)}';

  /// شنبه ۱۰ آبان ۱۴۰۵
  String dayTitle(DateTime t) {
    final l = toTehran(t);
    final j = toJalali(l);
    final wd = (persian ? _faWeekdays : _enWeekdays)[l.weekday];
    final m = (persian ? _faMonths : _enMonths)[j.month - 1];
    return _d('$wd ${j.day} $m ${j.year}');
  }

  JalaliDate jalaliDay(DateTime t) => toJalali(toTehran(t));

  String number(Object v) => _d('$v');
}

DateTime? parseServerTime(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
