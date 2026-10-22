import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/ui.dart';
import '../reference/inspire_search_help.dart';
import '../reviews/reviews_page.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.initialSection});

  /// Optional section id to scroll to on open (e.g. `inspire`).
  final String? initialSection;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  static const _ids = <String>[
    'start',
    'search',
    'inspire',
    'pages',
    'values',
    'place',
    'codes',
    'references',
    'display',
    'data',
    'faq',
  ];

  final ScrollController _controller = ScrollController();
  String? _activeId;
  final Map<String, GlobalKey> _keys = {for (final id in _ids) id: GlobalKey()};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(initial);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jump(String id) {
    setState(() => _activeId = id);
    final key = _keys[id];
    if (key != null) scrollToOutlineTarget(key, alignment: 0.03);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final zh = strings.lang.name == 'zh';
    String t(String cn, String en) => zh ? cn : en;
    final palette = context.palette;

    final sections = <_HelpSectionData>[
      _HelpSectionData(
        id: 'start',
        title: t('快速开始', 'Quick start'),
        children: [
          _bullet(
            context,
            t(
              '在查询页搜索粒子名、PDG ID、别名或 DOI/INSPIRE 标识符。例子：pi0、S032、J/psi、X(3872)、10.1103/PhysRevD.98.030001。',
              'Search particle names, PDG IDs, aliases, or DOI/INSPIRE identifiers. Examples: pi0, S032, J/psi, X(3872), 10.1103/PhysRevD.98.030001.',
            ),
          ),
          _bullet(
            context,
            t(
              '搜索范围可限定为全部、粒子、性质/专题、衰变或文献。结果中的粒子、系列、测量和文献都可以直接打开。',
              'Limit the scope to all, particles, properties/topics, decays, or references. Particles, series, measurements, and references in the results all open directly.',
            ),
          ),
          _bullet(
            context,
            t(
              '粒子页按“性质 / 衰变 / 文献”分栏；系列页展示当前汇总、全部测量、历史汇总和跨版趋势图。',
              'A particle page is split into Properties / Decays / References. A series page shows the current summary, all measurements, historical summaries, and a cross-edition trend chart.',
            ),
          ),
          _bullet(
            context,
            t(
              '收藏用于保存常看的条目；最近查询保存在本机，可在设置中清除。',
              'Favorites keep frequently used entries; recent searches are stored locally and can be cleared in Settings.',
            ),
          ),
          _bullet(
            context,
            t(
              '笔记保存在独立的本机数据库中，可从粒子、性质/系列、文献页或“笔记”页添加；不会写入 PDG 快照。',
              'Notes live in a separate local database and can be added from particle, property/series and reference pages or the Notes page; the PDG snapshot is never written.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'notes',
        title: t('笔记与标注', 'Notes and annotations'),
        children: [
          _bullet(
            context,
            t(
              '笔记只保存在本机数据库中，不写入 PDG 快照；换设备前请在设置里导出备份。',
              'Notes are stored only in the local database and never written into the PDG snapshot; export a backup before switching devices.',
            ),
          ),
          _bullet(
            context,
            t(
              '笔记正文里的 Markdown 链接只用于跳转；Evidence 依据笔记上方的锚点，修改链接不会改变锚点。',
              'Markdown links in a note body are navigation only. Evidence reads the anchors above the body; editing a link never changes an anchor.',
            ),
          ),
          _bullet(
            context,
            t(
              '证据页的数值来自只读 PDG 快照，编辑笔记不会修改 PDG 数据。',
              'Evidence values come from the read-only PDG snapshot; editing a note never edits PDG data.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'search',
        title: t('搜索与导航', 'Search and navigation'),
        children: [
          _glossary(
            context,
            t('支持的搜索键', 'Search keys'),
            t(
              '粒子名和常见写法（B+、B_s0、K0S）、PDG ID（M176、S032）、别名（X(3872)）、DOI、INSPIRE recid，以及文献题名中的词。',
              'Particle names and common spellings (B+, B_s0, K0S), PDG IDs (M176, S032), aliases (X(3872)), DOIs, INSPIRE recids, and words in reference titles.',
            ),
          ),
          _glossary(
            context,
            t('范围与结果', 'Scope and results'),
            t(
              '“全部”会合并多个索引；粒子/性质结果按 PDG 条目组织，文献结果可按 DOI 或 document_id 打开。结果数量受查询上限约束，分页/继续加载会标明。',
              '“All” merges several indexes; particle/property results are organized by PDG entries, and reference results open by DOI or document_id. Result counts are bounded, with paging/load-more disclosed.',
            ),
          ),
          _glossary(
            context,
            t('快捷操作', 'Shortcuts'),
            t(
              '在主界面用 ⌘1 / ⌘2 / ⌘3 / ⌘4 切换查询、收藏、笔记、设置；⌘F 聚焦查询框。顶栏 ←/→（⌘[ / ⌘]）在详情历史中后退/前进；详情页也可用侧栏的父子链接导航。',
              'On the main screen, ⌘1 / ⌘2 / ⌘3 / ⌘4 switch Search, Favorites, Notes, and Settings; ⌘F focuses the search field. Use ←/→ in the top bar (⌘[ / ⌘]) to go back/forward through detail history; sidebar parent/child links also work.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'inspire',
        title: t('INSPIRE 搜索语法', 'INSPIRE search syntax'),
        children: [const InspireSearchHelp(showTitle: false)],
      ),
      _HelpSectionData(
        id: 'pages',
        title: t('页面结构', 'Screens'),
        children: [
          _glossary(
            context,
            t('粒子页', 'Particle page'),
            t(
              '身份卡给出电荷、自旋、宇称、C/G 等；下面的性质列表按 PDG 系列组织。属性数量、衰变模式和文献数都可点击跳转。',
              'The identity card shows charge, spin, parity, C/G, etc.; the property list is organized by PDG series. Property, decay-mode, and reference counts are clickable.',
            ),
          ),
          _glossary(
            context,
            t('系列页 / 性质页', 'Series page'),
            t(
              '一个“系列”是一项被 PDG 持续汇总的量（如质量、宽度、分支比）。页面顶部是当前汇总，下面是完整测量和历史版本；趋势按钮只对跨版可比较的系列出现。',
              'A “series” is a quantity PDG summarizes over time (mass, width, branching fraction). Current summaries are at the top, followed by all measurements and historical editions; the trend button appears only for comparable series.',
            ),
          ),
          _glossary(
            context,
            t('测量卡', 'Measurement card'),
            t(
              '展示单篇文献的测量值、误差、单位、实验/方法代码、条件、文献和原始字段。误差可展开查看 total/stat/syst 分量；一个测量可能有多个 VALUE 列。',
              'Shows one paper’s value, errors, unit, experiment/method code, conditions, reference, and raw fields. Expand errors for total/stat/syst components; one measurement may have several VALUE columns.',
            ),
          ),
          _glossary(
            context,
            t('上下文侧栏', 'Context sidebar'),
            t(
              '宽屏时提供 See also、父级、同章节、性质和衰变模式快捷入口。侧栏不是第二份数据源，链接都指向同一个只读快照。',
              'On wide screens it provides See also, parent, sibling, property, and decay-mode shortcuts. It is not a second data source; every link points to the same read-only snapshot.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'values',
        title: t('汇总、测量和误差', 'Summaries, measurements, and errors'),
        children: [
          _glossary(
            context,
            t('PDG 汇总（Summary）', 'PDG summary'),
            t(
              'PDG 在一个版次中给出的官方值。value_type 说明它是加权平均、拟合、评估还是最佳限值；只有 in_summary_table=1 的行才属于 Summary Table。',
              'The official value for one PDG edition. value_type says whether it is a weighted average, fit, evaluation, or best limit; only rows with in_summary_table=1 belong to the Summary Table.',
            ),
          ),
          _glossary(
            context,
            t('测量（Measurement）', 'Measurement'),
            t(
              '一篇实验或理论文献报告的独立结果，通常含有若干数值列。测量级条件（实验、方法、反应、事件数）与数值列级误差/纳入标志是不同层级。',
              'An independent result reported by an experimental or theoretical paper, usually with several value columns. Measurement-level conditions (experiment, method, reaction, event count) are distinct from value-column errors/inclusion flags.',
            ),
          ),
          _glossary(
            context,
            t('当前汇总 / 历史汇总', 'Current / historical summaries'),
            t(
              '“当前”指快照版次（PDG 2026）的汇总；历史汇总按 edition 分组。没有当前汇总的系列仍保留测量，页面会说明“当前版未收录”。',
              '“Current” means the snapshot edition (PDG 2026); historical summaries are grouped by edition. A series without a current summary still keeps its measurements, and the page says so.',
            ),
          ),
          _glossary(
            context,
            t('used_in_average / used_in_fit', 'used_in_average / used_in_fit'),
            t(
              '某个具体数值列是否进入本 listing 的 average/fit 计算。它是数值列级标志，不等于 PDG 的 value_type，也不等于整个测量是否“有效”。',
              'Whether a specific value column entered this listing’s average/fit calculation. It is a value-column flag, not the PDG value_type and not a statement that the whole measurement is invalid.',
            ),
          ),
          _glossary(
            context,
            t('严格汇总选择', 'Strict summary selection'),
            t(
              '当同一系列有多条候选、或存在多个 Summary Table 行时，应用会显示“多个候选/不唯一”，不会按 sort 或第一条擅自选一个。这是为了避免把有歧义的 PDG 数据伪装成唯一官方值。',
              'When a series has several candidates or multiple Summary Table rows, the app shows “multiple candidates / not unique” instead of silently taking the first row by sort. This avoids presenting ambiguous PDG data as one official value.',
            ),
          ),
          _glossary(
            context,
            t('误差与单位', 'Errors and units'),
            t(
              '± 是对称误差；+a−b 是非对称误差，a 和 b 分别用于上、下侧。stat 和 syst 是分量，不能被自动相加成总误差；单位来自 unit_text，显示时可能用 ×10^n 缩放。',
              '± is symmetric; +a−b is asymmetric, with a and b for the upper and lower sides. stat and syst are components and are not automatically summed; units come from unit_text and may be scaled by ×10^n.',
            ),
          ),
          _glossary(
            context,
            t('CL / 置信水平', 'CL / confidence level'),
            t(
              'CL=90%、95% 等表示限值或区间的置信水平。应用保留 99.85% 这类小数，不会四舍五入成 100%。',
              'CL=90%, 95%, etc. is the confidence level of a limit or interval. Values such as 99.85% are kept and not rounded to 100%.',
            ),
          ),
          _glossary(
            context,
            t('S / scale factor', 'S / scale factor'),
            t(
              'PDG 对输入测量误差进行放大时给出的比例因子，记录在 pdgdata.scale_factor。误差已经按该因子处理，应用不会再次乘入显示值。',
              'The scale factor PDG used to enlarge input errors, recorded in pdgdata.scale_factor. Errors are already treated with it; the app does not apply it a second time.',
            ),
          ),
          _glossary(
            context,
            t('限值类型', 'Limit types'),
            t(
              'U = 上限，L = 下限，R = 区间，X = 排除区间；它们不是中心值加对称误差。',
              'U = upper limit, L = lower limit, R = range, X = excluded range; these are not a central value with symmetric errors.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'place',
        title: t(
          'PLACE：测量在 listing 中的位置',
          'PLACE: where a measurement is placed',
        ),
        children: [
          _bullet(
            context,
            t(
              '当前快照没有附带 place 码表；以下按 PDG RedBook 的 MEASUREMENT.PLACE 定义解释。它不是实验地点，也不是数据质量等级。',
              'The snapshot does not bundle a place code table; the following follows the PDG RedBook definition of MEASUREMENT.PLACE. It is not an experiment location or a data-quality grade.',
            ),
          ),
          _glossary(
            context,
            'U',
            t(
              'used 部分：该测量被列入“used”，可作为 average/fit 的候选。它不保证一定被最终采用。',
              'Used portion: the measurement is in the used block and is a candidate for averages/fits. It is not guaranteed to be selected.',
            ),
          ),
          _glossary(
            context,
            'N',
            t(
              'not used 部分：该测量不参与任何 summary；也包括不是简单“值 ± 误差”的条目。N 不等于数据无效。',
              'Not-used portion: the measurement does not enter any summary; this also covers entries that are not simple value±error rows. N does not mean invalid.',
            ),
          ),
          _glossary(
            context,
            'L',
            t(
              'used 部分中的最佳限值（粗体），并会复制到 RESULT SUMMARY，供汇总程序使用。',
              'A best limit in the used block (bold), copied to RESULT SUMMARY for the summarization machinery.',
            ),
          ),
          _glossary(
            context,
            'B',
            t(
              'used 部分中的最佳限值（粗体），但不会复制到 RESULT SUMMARY。它和 L 的区别就是是否进入 RESULT SUMMARY；两者都不是普通中心值测量。',
              'A best limit in the used block (bold) but not copied to RESULT SUMMARY. This is the difference from L; neither is an ordinary central-value measurement.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'codes',
        title: t(
          'value_type、flags 和内部字段',
          'value_type, flags, and internal fields',
        ),
        children: [
          _glossary(
            context,
            t('常见 value_type', 'Common value_type codes'),
            t(
              'AC = PDG 加权平均；FC/DR = PDG 拟合；V = 由相关量测量得到的评估；L = 最佳限值；OL = PDG 评估限值；E = PDG 估计；O = 无默认说明的 PDG 评估。页面会同时显示英文 indicator（OUR AVERAGE / OUR FIT / OUR EVALUATION 等）。',
              'AC = PDG weighted average; FC/DR = PDG fit; V = evaluation from related measurements; L = best limit; OL = PDG evaluated limit; E = PDG estimate; O = PDG evaluation without a default description. The English indicator (OUR AVERAGE / OUR FIT / OUR EVALUATION, etc.) is shown alongside.',
            ),
          ),
          _glossary(
            context,
            t('flags', 'flags'),
            t(
              'PDG 分类/属性标记，例如 M/B 表示介子/重子类别，A 备选、D 默认、0 中性、1 单电荷、2 双电荷、s 特殊条目。应用显示解码后的标签，同时保留原码。',
              'PDG classification/attribute markers, e.g. M/B for meson/baryon categories, A alternative, D default, 0 neutral, 1 singly charged, 2 doubly charged, s special. The app shows decoded labels and keeps the raw code.',
            ),
          ),
          _glossary(
            context,
            t(
              'PDG ID / pdgdata # / pdgmeasurement #',
              'PDG ID / pdgdata # / pdgmeasurement #',
            ),
            t(
              'PDG ID 是物理条目标识（M176、S032）；pdgdata/pdgmeasurement # 是数据库内部行号。普通查询可忽略内部行号，详细模式才显示。',
              'A PDG ID identifies a physics entry (M176, S032); pdgdata/pdgmeasurement # are internal database row IDs. Ordinary lookups can ignore them; only detailed mode shows them.',
            ),
          ),
          _glossary(
            context,
            t('文本与原始字段', 'Text and raw fields'),
            t(
              'PDG 的说明文字保留原文；能识别的粒子名和公式会排版，无法识别的片段安全回退为原文。原始字段面板可查看该行的全部列和值。',
              'PDG explanatory text is kept as source. Recognized particle names and formulas are typeset; unrecognized fragments fall back literally. The raw-fields panel shows every column and value for the row.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'references',
        title: t('文献和标识符', 'References and identifiers'),
        children: [
          _glossary(
            context,
            'DOI / INSPIRE',
            t(
              'DOI 是出版标识；INSPIRE 是 HEP 文献数据库标识。文献页可打开 DOI/INSPIRE，或复制 INSPIRE BibTeX。',
              'DOI identifies the publication; INSPIRE is the HEP literature database identifier. A reference page can open DOI/INSPIRE or copy INSPIRE BibTeX.',
            ),
          ),
          _glossary(
            context,
            t('cite key', 'cite key'),
            t(
              'INSPIRE BibTeX 条目的引用键，例如 ATLAS:2023jfq；显示在 INSPIRE 标识符旁。',
              'The citation key of the INSPIRE BibTeX entry, e.g. ATLAS:2023jfq; shown beside the INSPIRE identifier.',
            ),
          ),
          _glossary(
            context,
            t('题名补全', 'Title enrichment'),
            t(
              '快照中缺失的题名可按需通过 DOI/Crossref 获取；页面会标明来源，原始快照 title 不会被改写。',
              'A missing title can be fetched on demand through DOI/Crossref; the source is labelled and the raw snapshot title is not overwritten.',
            ),
          ),
          _glossary(
            context,
            t('文献页的反向关系', 'Reverse links'),
            t(
              '文献页列出关联的测量和 series；没有测量关联的文献仍会保留并可搜索。不同 document_id 的文献不会仅因 DOI 相同被合并。',
              'A reference page lists linked measurements and series; references without measurements are still kept and searchable. Different document_ids are not merged just because they share a DOI.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'display',
        title: t('显示、侧栏与设置', 'Display, sidebar, and settings'),
        children: [
          _glossary(
            context,
            t('详细模式 / 简约版', 'Detailed / simple mode'),
            t(
              '详细模式显示原始字段、flags、内部行号和快照哈希；关闭后隐藏这些技术内容，只保留性质、测量、衰变和文献。设置修改会立即作用于已打开的页面。',
              'Detailed mode shows raw fields, flags, internal row IDs, and the snapshot hash. Turning it off hides these technical items and keeps properties, measurements, decays, and references. Changes apply immediately to open pages.',
            ),
          ),
          _glossary(
            context,
            t('桌面侧边栏', 'Desktop sidebar'),
            t(
              '自动：≥620 px 显示；始终显示：≥480 px 保留；关闭：不显示。宽度随窗口在 240/280/320 px 之间调整。窗口低于所选下限时仍会隐藏，以保证正文可读。',
              'Auto: show at ≥620 px; Always: keep at ≥480 px; Off: hide. Width adapts between 240/280/320 px. Below the selected bound it still hides to keep the content readable.',
            ),
          ),
          _glossary(
            context,
            t('主题、语言、字体大小', 'Theme, language, text size'),
            t(
              '主题跟随系统或强制浅/深色；语言支持中/英；字体大小与系统缩放叠加，最终限制在 0.8–2.0 倍。',
              'Theme follows the system or is forced light/dark; language supports Chinese/English; text size combines with system scaling and is clamped to 0.8–2.0×.',
            ),
          ),
          _glossary(
            context,
            t('复制和选择', 'Copy and selection'),
            t(
              '卡片和页头的复制按钮可复制数值、测量或 BibTeX；数学排版数值用复制按钮，普通正文可选择复制。',
              'Copy buttons on cards and headers copy values, measurements, or BibTeX; typeset numbers use that button, while ordinary text is selectable.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'data',
        title: t('数据与离线快照', 'Data and offline snapshot'),
        children: [
          _bullet(
            context,
            t(
              '应用使用随包安装的 PDG 2026 只读快照，离线可用；首次安装时校验哈希，之后在文件大小或修改时间变化时重新校验，并记录 sidecar 结果。',
              'The app uses a bundled read-only PDG 2026 snapshot and works offline; the hash is checked on first install and whenever the installed copy changes, with the result recorded in a sidecar.',
            ),
          ),
          _bullet(
            context,
            t(
              '快照包含 PDG 条目、测量、数值列、文献和说明文字；应用不会写回数据库，设置/收藏保存在独立的本机 user store。',
              'The snapshot contains PDG entries, measurements, value columns, references, and explanatory text. The app never writes back to the database; settings/favorites live in a separate local user store.',
            ),
          ),
          _bullet(
            context,
            t(
              '笔记使用独立的本机数据库（应用数据目录中的 user.db），可复制为 Markdown，也可在笔记页把全部笔记导出为 JSON。',
              'Notes use a separate local database (user.db in the application data directory), can be copied as Markdown, and the Notes page can export all notes as JSON.',
            ),
          ),
          _bullet(
            context,
            t(
              'Crossref 题名补全和 INSPIRE BibTeX/cite-key 只在明确操作或需要时联网；核心查询不依赖网络。',
              'Crossref title enrichment and INSPIRE BibTeX/cite-key use the network only on explicit actions or when needed; core lookups do not depend on the network.',
            ),
          ),
          _bullet(
            context,
            t(
              '官方数据库没有 pdgLive 粒子页上的“was …”旧名和摘要说明，也没有摘要里引用的部分文献。应用为此附带了一个补丁库：粒子页会显示旧名、摘要和可点击的引用；这些引用若不在官方文献表中，点开的是应用内的题录页（数据由 INSPIRE 补全），不会跳出到网页。补丁每年随 PDG 版次重新生成。',
              'The official database has neither the “was …” rename and summary prose shown on pdgLive particle pages, nor some works cited in those summaries. The app ships a patch database: particle pages show the rename, the summary and tappable citations; a citation missing from the official reference table opens an in-app record completed from INSPIRE instead of a web page. The patch is regenerated with each PDG edition.',
            ),
          ),
        ],
      ),
      _HelpSectionData(
        id: 'faq',
        title: t('常见问题', 'FAQ'),
        children: [
          _glossary(
            context,
            t('为什么没有“官方首选”数值？', 'Why is there no preferred value?'),
            t(
              '该系列可能没有 Summary Table 行，或同时存在多个候选/多个 Summary Table 行。应用选择显示“多个候选”，而不是按行号猜一个；这是设计上的严格选择规则。',
              'The series may have no Summary Table row, or several candidates/Summary Table rows. The app shows “multiple candidates” instead of guessing by row ID; this is a deliberate strict rule.',
            ),
          ),
          _glossary(
            context,
            t('为什么 place N 的测量还在显示？', 'Why is an N measurement still shown?'),
            t(
              'N 只表示它位于 listing 的 not used 部分，不等于数据无效；测量仍保留完整数值、误差和文献。',
              'N only means it sits in the not-used block, not that it is invalid; the measurement keeps its value, errors, and reference.',
            ),
          ),
          _glossary(
            context,
            t('为什么少数公式/粒子名仍是原文？', 'Why are a few formulas/names still raw?'),
            t(
              '排版层只转换能确定含义的片段；嵌套花括号、罕见 partial-wave 标记等无法安全解析时会保留 PDG 原文，避免生成错误公式。',
              'The typesetter converts only fragments whose meaning is certain. Nested braces and rare partial-wave tags that cannot be parsed safely stay as PDG source instead of becoming a wrong formula.',
            ),
          ),
          _glossary(
            context,
            t('为什么侧栏没有出现？', 'Why is the sidebar missing?'),
            t(
              '检查设置里的“桌面侧边栏”是否为关闭，以及窗口宽度是否低于自动/始终模式的下限；Home 分栏时侧栏按右侧详情面板宽度判断，而不是整个窗口宽度。',
              'Check whether Desktop sidebar is Off and whether the window is below the Auto/Always bound. In the Home split layout the decision uses the detail pane width, not the whole window width.',
            ),
          ),
          _glossary(
            context,
            t('数据多久更新？', 'How often is data updated?'),
            t(
              '当前快照是 PDG 2026；应用不自动下载新版。新快照需要通过构建流程替换并重新校验哈希。',
              'The current snapshot is PDG 2026; the app does not auto-download new editions. A new snapshot must be replaced through the build process and re-verified by hash.',
            ),
          ),
          _glossary(
            context,
            t('多阶段衰变怎么读？', 'How do I read a multi-stage decay?'),
            t(
              '原文含多个阶段箭头时，各项按原文顺序展示，不把不同阶段的产物合并成一个末态。',
              'When the source has several stage arrows, tokens are shown in source order; stages are not merged into one final state.',
            ),
          ),
          _glossary(
            context,
            t('属性目录怎么分组？', 'How is the property directory grouped?'),
            t(
              '按原始章节与类型排列；未知类型也保留入口，不会被丢弃。',
              'Grouped as published by section and type; uninterpreted types remain reachable instead of being dropped.',
            ),
          ),
          _glossary(
            context,
            t(
              '原始列里 NULL、空串和 0 有区别吗？',
              'Do NULL, empty string and 0 differ in raw columns?',
            ),
            t(
              '原始列按数据库原样显示：NULL、空字符串与 0 分别保留，不会被合并。',
              'Raw columns are shown as stored: NULL, the empty string and 0 stay distinct and are never merged.',
            ),
          ),
          _glossary(
            context,
            t('INSPIRE 检索需要联网吗？', 'Does INSPIRE search need the network?'),
            t(
              '需要联网。结果来自 INSPIRE，不改变本地 PDG 文献；支持 a、t、cn、doi、arxiv 等语法。',
              'Yes. Results come from INSPIRE and do not change local PDG references; a, t, cn, doi, arxiv and other INSPIRE operators are supported.',
            ),
          ),
          _glossary(
            context,
            t('为什么历史汇总不是每个版次都有？', 'Why is the historical summary incomplete?'),
            t(
              '只列出该系列实际存在的版次；同一版次的多行全部保留。',
              'Only editions actually present are listed; every row of an edition is retained.',
            ),
          ),
          _glossary(
            context,
            t(
              '系列页的定义文本为什么保持原样？',
              'Why does the definition text stay as stored?',
            ),
            t(
              '文本按数据库原文显示；标题与约定段落分别保留类型，不做重排。',
              'Text is shown as stored; headings and convention paragraphs keep their type and are not reflowed.',
            ),
          ),
          _glossary(
            context,
            t(
              '衰变目录的父子是物理级联吗？',
              'Is decay-directory parentage a physical cascade?',
            ),
            t(
              '不是。子项表示原文中的细化、排除条件或分组；展开只改变目录视图，不重新解释物理阶段。',
              'No. Children represent refinements, exclusions or groupings from the source; expanding only changes the directory view, not the physics.',
            ),
          ),
          _glossary(
            context,
            t(
              '相关量为什么不是分支分数？',
              'Why is a related quantity not a branching fraction?',
            ),
            t(
              '相关量保留自己的类型与定义；比值或宽度不会改称本模式的分支分数。',
              'Related quantities keep their own type and definition; a ratio or width is never relabelled as this branching fraction.',
            ),
          ),
        ],
      ),
    ];

    final intro = Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.l,
        Insets.m,
        Insets.l,
        Insets.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Particle Library 是离线 PDG 数据浏览器。本页按“怎么用 → 数据怎么读 → 字段/术语 → 常见问题”组织。',
              'Particle Library is an offline PDG data browser. This page is organized as “how to use → how to read values → fields/terms → FAQ”.',
            ),
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => AppNav.push<void>(context, const ReviewsPage()),
            icon: const Icon(Icons.menu_book_outlined, size: 17),
            label: Text(strings.reviewsTitle),
          ),
        ],
      ),
    );

    final tocEntries = [
      for (final section in sections) (id: section.id, title: section.title),
    ];

    final sectionWidgets = [
      for (final section in sections)
        _HelpSection(
          key: _keys[section.id],
          title: section.title,
          children: section.children,
        ),
    ];

    Widget content({required bool withIntro}) => SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.only(bottom: Insets.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [if (withIntro) intro, ...sectionWidgets],
      ),
    );

    return PageScaffold(
      maxWidth: 1240,
      title: Text(strings.helpTitle),
      subtitle: strings.helpSubtitle,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          if (!wide) {
            return SingleChildScrollView(
              controller: _controller,
              padding: const EdgeInsets.only(bottom: Insets.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      Insets.s,
                      Insets.l,
                      Insets.s,
                    ),
                    child: _HelpDirectory(
                      entries: tocEntries,
                      horizontal: true,
                      activeId: _activeId,
                      onTap: _jump,
                    ),
                  ),
                  const Divider(height: 1),
                  intro,
                  ...sectionWidgets,
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 236,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.l,
                    Insets.m,
                    Insets.s,
                    Insets.xxl,
                  ),
                  child: _HelpDirectory(
                    entries: tocEntries,
                    horizontal: false,
                    activeId: _activeId,
                    onTap: _jump,
                  ),
                ),
              ),
              Expanded(child: content(withIntro: true)),
            ],
          );
        },
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _glossary(BuildContext context, String term, String text) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HelpSectionData {
  const _HelpSectionData({
    required this.id,
    required this.title,
    required this.children,
  });

  final String id;
  final String title;
  final List<Widget> children;
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, 0),
      child: SectionCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _HelpDirectory extends StatelessWidget {
  const _HelpDirectory({
    required this.entries,
    required this.horizontal,
    required this.onTap,
    this.activeId,
  });

  final List<({String id, String title})> entries;
  final bool horizontal;
  final void Function(String id) onTap;
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final zh = AppScope.of(context).strings.lang.name == 'zh';
    final heading = Text(
      zh ? '目录' : 'Contents',
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: palette.textSecondary, fontWeight: FontWeight.w600),
    );
    if (horizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final entry in entries)
                TextButton(
                  onPressed: () => onTap(entry.id),
                  style: TextButton.styleFrom(
                    foregroundColor: entry.id == activeId
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    textStyle: entry.id == activeId
                        ? const TextStyle(fontWeight: FontWeight.w600)
                        : null,
                  ),
                  child: Text(entry.title),
                ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 6),
        for (final entry in entries)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTap(entry.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                entry.title,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}
