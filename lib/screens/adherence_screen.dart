import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/adherence_service.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_ui.dart';

class AdherenceScreen extends StatefulWidget {
  const AdherenceScreen({super.key});

  @override
  State<AdherenceScreen> createState() => _AdherenceScreenState();
}

class _AdherenceScreenState extends State<AdherenceScreen> {
  AdherencePeriod period = AdherencePeriod.week;
  DateTime rangeStart = DateUtils.dateOnly(DateTime.now());
  DateTime rangeEnd = DateUtils.dateOnly(DateTime.now());

  Future<void> _selectRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: rangeStart, end: rangeEnd),
      helpText: 'เลือกช่วงวันที่ดูความสม่ำเสมอ',
      saveText: 'เลือกช่วงนี้',
    );
    if (selected != null) {
      setState(() {
        period = AdherencePeriod.custom;
        rangeStart = selected.start;
        rangeEnd = selected.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final report = const AdherenceService().calculate(
        period: period,
        now: DateTime.now(),
        drugs: controller.drugs,
        intakes: controller.intakeHistory,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd);
    return Scaffold(
      backgroundColor: MeDisColors.background,
      appBar: const MeDisAppBar('ความสม่ำเสมอในการทานยา'),
      body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: MeDisSpace.pagePadding,
          children: [
            DropdownButtonFormField<AdherencePeriod>(
              initialValue: period,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'รูปแบบรายงาน',
                prefixIcon: Icon(Icons.bar_chart_outlined),
              ),
              items: const [
                DropdownMenuItem(
                    value: AdherencePeriod.day, child: Text('รายวัน')),
                DropdownMenuItem(
                    value: AdherencePeriod.week, child: Text('รายสัปดาห์')),
                DropdownMenuItem(
                    value: AdherencePeriod.month, child: Text('รายเดือน')),
                DropdownMenuItem(
                    value: AdherencePeriod.custom,
                    child: Text('กำหนดช่วงวันที่')),
              ],
              onChanged: (value) {
                if (value == null) return;
                if (value == AdherencePeriod.custom) {
                  _selectRange();
                } else {
                  setState(() {
                    period = value;
                    rangeEnd = DateUtils.dateOnly(DateTime.now());
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _selectRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                  'ตั้งแต่ ${_shortDate(report.start)} ถึง ${_shortDate(report.end)}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 18),
            _OverallCard(report: report),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(
                  child: Text('แยกตามประเภทยา',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700))),
              Text('${report.drugs.length} ประเภท',
                  style: const TextStyle(color: MeDisColors.muted))
            ]),
            const SizedBox(height: 10),
            if (report.drugs.isEmpty)
              const MeDisEmptyState(
                  icon: Icons.bar_chart_outlined,
                  title: 'ยังไม่มีข้อมูลยาเพื่อคำนวณ',
                  message: 'เริ่มบันทึกการทานยา แล้วกลับมาดูแนวโน้มที่นี่'),
            ...report.drugs.map((item) => _DrugRateCard(item: item)),
            const SizedBox(height: 8),
            const Text(
              'คำนวณจากจำนวนมื้อยาที่ควรทาน เทียบกับรายการที่กด “ทานแล้ว” ภายในช่วงเวลาที่เลือก',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: MeDisColors.subtle),
            ),
          ]),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.report});
  final AdherenceReport report;

  @override
  Widget build(BuildContext context) {
    final percent = (report.rate * 100).round();
    final color = _rateColor(report.rate);
    return Card(
      child: Padding(
        padding: MeDisSpace.pagePadding,
        child: Row(children: [
          SizedBox.square(
            dimension: 112,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.square(
                  dimension: 104,
                  child: CircularProgressIndicator(
                      value: report.rate,
                      strokeWidth: 11,
                      strokeCap: StrokeCap.round,
                      backgroundColor: MeDisColors.border,
                      color: color)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$percent%',
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w700)),
                const Text('ภาพรวม',
                    style: TextStyle(fontSize: 12, color: MeDisColors.muted))
              ])
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ความสม่ำเสมอในการทานยา',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text(_dateRange(report.start, report.end),
                    style: const TextStyle(color: MeDisColors.muted)),
                const SizedBox(height: 13),
                Wrap(spacing: 20, runSpacing: 8, children: [
                  _Count(label: 'ทานแล้ว', value: report.taken),
                  _Count(label: 'ควรทาน', value: report.expected),
                ])
              ]))
        ]),
      ),
    );
  }
}

class _DrugRateCard extends StatelessWidget {
  const _DrugRateCard({required this.item});
  final DrugAdherence item;

  @override
  Widget build(BuildContext context) {
    final percent = (item.rate * 100).round();
    final color = _rateColor(item.rate);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(children: [
          Row(children: [
            Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                    color: MeDisColors.primarySoft,
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.medication_outlined,
                    color: MeDisColors.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.drug.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${item.taken} จาก ${item.expected} ครั้ง',
                      style: const TextStyle(color: MeDisColors.muted))
                ])),
            Text('$percent%',
                style: TextStyle(
                    color: color, fontSize: 19, fontWeight: FontWeight.w700))
          ]),
          const SizedBox(height: 13),
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                  value: item.rate,
                  minHeight: 9,
                  backgroundColor: MeDisColors.border,
                  color: color))
        ]),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$value',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: MeDisColors.subtle))
      ]);
}

Color _rateColor(double rate) {
  if (rate >= .8) return MeDisColors.success;
  if (rate >= .5) return MeDisColors.warning;
  return MeDisColors.error;
}

String _dateRange(DateTime start, DateTime end) =>
    '${start.day}/${start.month}/${start.year + 543} – ${end.day}/${end.month}/${end.year + 543}';

String _shortDate(DateTime value) =>
    '${value.day}/${value.month}/${value.year + 543}';
