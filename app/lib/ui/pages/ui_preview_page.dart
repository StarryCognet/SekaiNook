import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../fl_ui/card.dart';
import '../../fl_ui/list.dart';
import '../../fl_ui/null_status.dart';
import '../../fl_ui/scaffold.dart';
import '../../fl_ui/search_field.dart';
import '../../fl_ui/segmented_control.dart';
import '../../fl_ui/skeleton.dart';
import '../../ui/widgets/app_sheet.dart';

/// FlClash / fl_ui 组件的「试样间」。
///
/// 这里**不挂主壳**（不在 MainShell 里），所以没有浮层顶栏与悬浮胶囊，
/// 能把 `CommonScaffold` 的完整页面骨架看清楚：折叠顶栏、搜索、溢出菜单、
/// 内容区与底部的真实关系。
///
/// 用途：判断「把页面范式全部换成 FlClash」到底合不合 SekaiNook 的胃口 ——
/// 用手机滑一遍这个页面，比看设计文档快。
class UiPreviewPage extends StatefulWidget {
  const UiPreviewPage({super.key});

  @override
  State<UiPreviewPage> createState() => _UiPreviewPageState();
}

class _UiPreviewPageState extends State<UiPreviewPage> {
  String _section = '卡片';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'FlClash 试样间',
      // 这页不在 MainShell 里，是从「设置 → 管理员 → 高级 · 排障」go 进来的：
      // 用 go 进门时栈里只有这一页，不自己指定返回就既没有返回箭头、系统返回还会退出 App
      backAction: () => context.go('/settings'),
      onKeywordsUpdate: (List<String> keywords) {},
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          SegmentedControl<String>(
            segments: const <(String, String)>[
              ('卡片', '卡片'),
              ('列表', '列表'),
              ('空态', '空态'),
            ],
            value: _section,
            onChanged: (String value) => setState(() => _section = value),
          ),
          const SizedBox(height: 16),
          switch (_section) {
            '列表' => _buildList(),
            '空态' => _buildNullStatus(),
            _ => _buildCards(),
          },
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _openSheet,
              child: const Text('打开 SnapSheet 面板'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const InfoHeader(info: Info(label: 'FlClash 卡片范式')),
        CommonCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CommonCard', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '带按压高亮、圆角与 Surface 层级的卡片。'
                '点一下能看出它和 AppCard 的手感差异。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CommonCard(
          padding: const EdgeInsets.all(16),
          onPressed: () {},
          child: const Text('可点击的 CommonCard'),
        ),
        const SizedBox(height: 24),
        const SkeletonPill(width: double.infinity, height: 14),
        const SizedBox(height: 8),
        const SkeletonPill(width: 220, height: 14),
        const SizedBox(height: 8),
        const SkeletonPill(width: 160, height: 14),
      ],
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SearchField(
            onChanged: (String value) => setState(() => _query = value),
          ),
        ),
        for (final String item in <String>['首页', '家庭', '花园', '设置'])
          if (_query.isEmpty || item.contains(_query))
            ListItem(
              leading: const Icon(Icons.circle_outlined),
              title: Text(item),
              subtitle: Text('FlClash 行式列表 · $_query'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
        if (_query.isNotEmpty &&
            !<String>['首页', '家庭', '花园', '设置']
                .any((String item) => item.contains(_query)))
          const SizedBox(
            height: 240,
            child: NullStatus(
              label: '没有匹配项',
              description: '换个关键词试试',
              illustration: NullStatusIllustration.search,
            ),
          ),
      ],
    );
  }

  Widget _buildNullStatus() {
    return const SizedBox(
      height: 360,
      child: NullStatus(
        label: '今天还没有记录',
        description: 'FlClash 的空态带插画与入场动画，'
            '比现在的 ErrorView / EmptyView 更有存在感。',
        illustration: NullStatusIllustration.logs,
      ),
    );
  }

  Future<void> _openSheet() async {
    await showAppSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SnapSheet',
              style: Theme.of(sheetContext).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '从底部弹出、盖住悬浮导航栏的面板：跟手拖拽、下拉关闭、'
              '背景压暗。打卡与提醒编辑都会换成它。',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
