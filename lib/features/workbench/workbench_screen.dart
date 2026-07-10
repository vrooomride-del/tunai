/// TUNAI PRO — Engineering Workbench screen.
///
/// Hosts two tabs:
///   ADAU1701 Test — Phase 1 hardware write test (WONDOM JAB4 / Miumax original DSP)
///   ADAU1466      — Master Volume L/R write via USBi (TUNAI v0.8 experimental DSP)
///
/// Accessible only from the TUNAI PRO menu in MORE → Factory.
library;

import 'package:flutter/material.dart';
import 'tabs/adau1701_test_tab.dart';
import 'tabs/hardware_tab.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'TUNAI PRO  ·  ENGINEERING WORKBENCH',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            color: Colors.white54,
            fontWeight: FontWeight.w400,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 11, letterSpacing: 1.2),
          tabs: const [
            Tab(text: 'ADAU1701  JAB4'),
            Tab(text: 'ADAU1466  MASTER VOL'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          Adau1701TestTab(),
          HardwareTab(),
        ],
      ),
    );
  }
}
